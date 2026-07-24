import Foundation
import Observation
import ZayFlowCore

@MainActor
@Observable
final class AppModel {
    enum Section: String, CaseIterable, Identifiable {
        case sell = "Sell"
        case stock = "Stock"
        case activity = "Activity"
        case reports = "Reports"
        case more = "More"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .sell: "cart.fill"
            case .stock: "shippingbox.fill"
            case .activity: "clock.arrow.circlepath"
            case .reports: "chart.bar.fill"
            case .more: "ellipsis.circle.fill"
            }
        }
    }

    enum ProductSort: String, CaseIterable, Identifiable {
        case name = "Name"
        case stock = "Stock level"
        case price = "Price"

        var id: String { rawValue }
    }

    private let database: AppDatabase
    private let sessionStore: SessionStore
    private let authService: AuthService

    var session: AuthSession?
    var selectedMode: LoginMode = .pos
    var selectedSection: Section = .sell
    var products: [StoreProduct] = []
    var searchText = ""
    var selectedCategory = "All"
    var productSort: ProductSort = .name
    var cartLines: [CartDisplayLine] = []
    var sales: [SaleSummary] = []
    var organisationSnapshot: OrganisationSnapshot?
    var isCartPresented = false
    var isPOSShopPickerPresented = false
    var pendingSyncCount = 0
    var isSyncing = false
    var isCheckingCoordinator = false
    var coordinatorHealthMessage: String?
    var lastError: String?

    init(database: AppDatabase, sessionStore: SessionStore = SessionStore(), authService: AuthService = AuthService()) throws {
        self.database = database
        self.sessionStore = sessionStore
        self.authService = authService
        session = try? sessionStore.load()
        if let session {
            selectedMode = session.mode
            try? registerCurrentDevice(session)
        }
        products = try database.fetchProducts(shopID: session?.shop?.id, deviceID: currentDeviceID)
        sales = try database.fetchSales(shopID: session?.shop?.id)
        refreshPendingSyncCount()
    }

    var isAuthenticated: Bool { session != nil }

    var canUseOrganisationDashboard: Bool {
        session?.user.role.canUseOrganisationDashboard == true
    }

    var availableSections: [Section] {
        guard let session else { return [] }
        return Section.allCases.filter { section in
            switch section {
            case .sell: session.user.canSell
            case .stock: session.user.canIntake || session.user.role.canUseOrganisationDashboard
            case .activity, .reports, .more: true
            }
        }
    }

    func signIn(mode: LoginMode, orgId: String, shopId: String, userId: String, password: String) async {
        do {
            let session: AuthSession
            if let localSession = try database.authenticateLocalDemo(mode: mode, orgId: orgId, shopId: mode == .pos ? shopId : nil, userId: userId, password: password) {
                session = localSession
            } else {
                session = try await authService.login(
                    mode: mode,
                    orgId: orgId,
                    shopId: mode == .pos ? shopId : nil,
                    userId: userId,
                    password: password
                )
            }
            try sessionStore.save(session)
            self.session = session
            try registerCurrentDevice(session)
            selectedMode = session.mode
            selectedSection = availableSections.first ?? .sell
            loadOrganisationData()
            reloadProducts()
            refreshPendingSyncCount()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        try? sessionStore.clear()
        session = nil
        selectedMode = .pos
        selectedSection = .sell
        cartLines.removeAll()
        organisationSnapshot = nil
    }

    func switchMode(_ mode: LoginMode) {
        switch mode {
        case .pos:
            requestPOSMode()
        case .organisationDashboard:
            switchToOrganisationDashboard()
        }
    }

    func requestPOSMode() {
        guard let session else { return }
        if let shop = session.shop {
            switchToPOS(shop: shop)
            return
        }
        if session.permittedShops.count == 1, let shop = session.permittedShops.first {
            switchToPOS(shop: shop)
            return
        }
        guard !session.permittedShops.isEmpty else {
            lastError = "No POS shops assigned."
            return
        }
        isPOSShopPickerPresented = true
    }

    func switchToPOS(shop: AuthSession.Shop) {
        guard let session, session.permittedShops.contains(where: { $0.id == shop.id }) else { return }
        let updated = AuthSession(
            mode: .pos,
            organization: session.organization,
            shop: shop,
            user: session.user,
            permittedShops: session.permittedShops,
            device: session.device,
            issuedAt: session.issuedAt
        )
        do {
            try sessionStore.save(updated)
            self.session = updated
            try registerCurrentDevice(updated)
            selectedMode = .pos
            selectedSection = availableSections.contains(.sell) ? .sell : (availableSections.first ?? .more)
            isPOSShopPickerPresented = false
            reloadProducts()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func switchToOrganisationDashboard() {
        guard let session, canUseOrganisationDashboard else { return }
        let updated = AuthSession(
            mode: .organisationDashboard,
            organization: session.organization,
            shop: nil,
            user: session.user,
            permittedShops: session.permittedShops,
            device: session.device,
            issuedAt: session.issuedAt
        )
        do {
            try sessionStore.save(updated)
            self.session = updated
            try registerCurrentDevice(updated)
            selectedMode = .organisationDashboard
            loadOrganisationData()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadOrganisationData() {
        guard let session else { return }
        do {
            try registerCurrentDevice(session)
            organisationSnapshot = try database.fetchOrganisationSnapshot(permittedShopIDs: session.permittedShops.map(\.id))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addOrganisationShop(code: String, name: String, city: String, address: String?) {
        do {
            try database.addOrganisationShop(code: code, name: name, city: city, address: address)
            refreshSessionFromLocalDemo()
            loadOrganisationData()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addOrganisationCatalogItem(name: String, sku: String, category: String, priceMajor: Int64, costMajor: Int64, shopIDs: [UUID], openingStock: Int64) {
        do {
            try database.addOrganisationCatalogItem(name: name, sku: sku, category: category, priceMajor: priceMajor, costMajor: costMajor, shopIDs: shopIDs, openingStock: openingStock)
            loadOrganisationData()
            reloadProducts()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func adjustOrganisationInventory(shopID: UUID, productID: UUID, deltaUnits: Int64, reason: String) {
        do {
            try database.adjustOrganisationInventory(shopID: shopID, productID: productID, deltaUnits: deltaUnits, reason: reason)
            loadOrganisationData()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addOrganisationUser(userCode: String, displayName: String, role: UserRole, password: String, shopIDs: [UUID], canSell: Bool, canIntake: Bool) {
        do {
            try database.addOrganisationUser(userCode: userCode, displayName: displayName, role: role, password: password, shopIDs: shopIDs, canSell: canSell, canIntake: canIntake)
            loadOrganisationData()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateDeviceCategoryRestrictions(deviceID: UUID, categories: Set<String>) {
        do {
            try database.updateDeviceCategoryRestrictions(deviceID: deviceID, categories: categories)
            loadOrganisationData()
            reloadProducts()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshSessionFromLocalDemo() {
        guard let session,
              let refreshed = try? database.authenticateLocalDemo(
                mode: session.mode,
                orgId: session.organization.code,
                shopId: session.shop?.code,
                userId: session.user.userCode,
                password: "demo"
              ) else { return }
        self.session = refreshed
        try? sessionStore.save(refreshed)
    }

    var categories: [String] {
        ["All"] + Set(products.map(\.category)).sorted()
    }

    var filteredProducts: [StoreProduct] {
        let matching = products.filter { product in
            let matchesCategory = selectedCategory == "All" || product.category == selectedCategory
            guard matchesCategory else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            let words = query.lowercased().split(separator: " ")
            let searchable = [product.name, product.localName, product.sku, product.category, product.barcode]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return words.allSatisfy { searchable.contains($0) }
        }
        switch productSort {
        case .name:
            return matching.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .stock:
            return matching.sorted { $0.stockQuantity > $1.stockQuantity }
        case .price:
            return matching.sorted { $0.unitPrice.minorUnits < $1.unitPrice.minorUnits }
        }
    }

    var cartCount: Int {
        cartLines.reduce(0) { $0 + Int($1.quantity.microUnits / Quantity.scale) }
    }

    var cartTotal: Money {
        cartLines.reduce(.mmk(0)) { partial, line in
            (try? partial.adding(line.total)) ?? partial
        }
    }

    var stockValue: Money {
        products.reduce(.mmk(0)) { partial, product in
            let value = (try? product.unitCost.multiplied(by: product.stockQuantity)) ?? .mmk(0)
            return (try? partial.adding(value)) ?? partial
        }
    }

    var salesToday: Money {
        let calendar = Calendar(identifier: .gregorian)
        return sales.filter { calendar.isDate($0.occurredAt, inSameDayAs: Date()) }
            .reduce(.mmk(0)) { partial, sale in
                (try? partial.adding(sale.grandTotal)) ?? partial
            }
    }

    var lowStockProducts: [StoreProduct] {
        products.filter { $0.stockQuantity <= $0.lowStockThreshold }
    }

    func addToCart(_ product: StoreProduct) {
        if let index = cartLines.firstIndex(where: { $0.product.id == product.id }) {
            let existing = cartLines[index]
            let next = (try? existing.quantity.adding(.units(1))) ?? existing.quantity
            cartLines[index] = CartDisplayLine(product: product, quantity: next)
        } else {
            cartLines.append(CartDisplayLine(product: product, quantity: .units(1)))
        }
    }

    func addToCart(barcode: String) -> Bool {
        guard let product = products.first(where: { $0.barcode?.caseInsensitiveCompare(barcode) == .orderedSame }) else {
            return false
        }
        addToCart(product)
        return true
    }

    func increment(_ line: CartDisplayLine) {
        guard let index = cartLines.firstIndex(where: { $0.id == line.id }) else { return }
        let next = (try? line.quantity.adding(.units(1))) ?? line.quantity
        cartLines[index] = CartDisplayLine(product: line.product, quantity: next)
    }

    func decrement(_ line: CartDisplayLine) {
        guard let index = cartLines.firstIndex(where: { $0.id == line.id }) else { return }
        if line.quantity <= .units(1) {
            cartLines.remove(at: index)
        } else {
            let next = (try? line.quantity.subtracting(.units(1))) ?? line.quantity
            cartLines[index] = CartDisplayLine(product: line.product, quantity: next)
        }
    }

    func clearCart() {
        cartLines.removeAll()
    }

    func completeSale(paymentMethod: PaymentMethod, amountTendered: Money) throws -> CompletedSale {
        guard session?.user.canSell == true else {
            throw AuthError.rejected("User is not allowed to sell")
        }
        guard let checkoutContext else {
            throw AuthError.rejected("Choose a POS shop before selling")
        }
        let request = CheckoutRequest(
            lines: cartLines.map { CheckoutLine(productId: $0.product.id, quantity: $0.quantity) },
            paymentMethod: paymentMethod,
            amountTendered: amountTendered
        )
        let completed = try database.completeSale(request, context: checkoutContext)
        cartLines.removeAll()
        products = try database.fetchProducts(shopID: session?.shop?.id, deviceID: currentDeviceID)
        sales = try database.fetchSales(shopID: session?.shop?.id)
        loadOrganisationData()
        return completed
    }

    func reloadProducts() {
        do {
            products = try database.fetchProducts(shopID: session?.shop?.id, deviceID: currentDeviceID)
            sales = try database.fetchSales(shopID: session?.shop?.id)
            if !categories.contains(selectedCategory) {
                selectedCategory = "All"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private var checkoutContext: CheckoutContext? {
        guard let session, let shop = session.shop else { return nil }
        guard let deviceId = currentDeviceID else { return nil }
        return CheckoutContext(
            organizationId: session.organization.id,
            shopId: shop.id,
            userId: session.user.id,
            deviceId: deviceId
        )
    }

    private var currentDeviceID: UUID? {
        guard let installationId = session?.device.installationId else { return nil }
        return UUID(uuidString: installationId)
    }

    private func registerCurrentDevice(_ session: AuthSession) throws {
        guard let deviceID = UUID(uuidString: session.device.installationId) else { return }
        try database.registerLocalDevice(
            deviceID: deviceID,
            organizationID: session.organization.id,
            shopID: session.shop?.id,
            label: "This iOS Device"
        )
    }

    func syncPendingOutbox(to pushEndpoint: URL, sharedSecret: String? = nil) async {
        isSyncing = true
        defer {
            isSyncing = false
            refreshPendingSyncCount()
        }
        do {
            let pending = try database.fetchPendingSyncEvents()
            guard !pending.isEmpty else { return }

            let events = try pending.map { event in
                try canonicalSyncEvent(event)
            }
            let body: [String: Any] = [
                "protocolVersion": 1,
                "deviceId": session?.device.installationId ?? "60000000-0000-4000-8000-000000000001",
                "organizationId": session?.organization.id.uuidString ?? "20000000-0000-4000-8000-000000000001",
                "locationId": session?.shop?.id.uuidString ?? "21000000-0000-4000-8000-000000000001",
                "events": events
            ]
            var request = URLRequest(url: pushEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let sharedSecret, !sharedSecret.isEmpty {
                request.setValue("Bearer \(sharedSecret)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let pushResponse = try JSONDecoder().decode(LocalCoordinatorPushResponse.self, from: data)
            guard pushResponse.ok else { throw LocalCoordinatorError.rejected("Coordinator rejected sync payload") }
            let pendingIds = Set(pending.map(\.eventId))
            let acceptedIds = Set(pushResponse.accepted.filter { $0.status == "accepted" }.map(\.eventId))
            let acknowledgedIds = pendingIds.intersection(acceptedIds)
            try database.markSyncEventsAcknowledged(Array(acknowledgedIds))
            let missingIds = pendingIds.subtracting(acceptedIds)
            if !missingIds.isEmpty {
                try database.markSyncEventsFailed(Array(missingIds), errorCode: "Coordinator did not acknowledge event")
                throw LocalCoordinatorError.rejected("Coordinator accepted \(acknowledgedIds.count) of \(pendingIds.count) events")
            }
            coordinatorHealthMessage = "Last push accepted \(acknowledgedIds.count) events."
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            let pendingIds = (try? database.fetchPendingSyncEvents().map(\.eventId)) ?? []
            try? database.markSyncEventsFailed(pendingIds, errorCode: error.localizedDescription)
        }
    }

    func checkLocalCoordinatorHealth(at healthEndpoint: URL, sharedSecret: String? = nil) async {
        isCheckingCoordinator = true
        defer { isCheckingCoordinator = false }
        do {
            var request = URLRequest(url: healthEndpoint)
            request.httpMethod = "GET"
            if let sharedSecret, !sharedSecret.isEmpty {
                request.setValue("Bearer \(sharedSecret)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let health = try JSONDecoder().decode(LocalCoordinatorHealthResponse.self, from: data)
            guard health.ok, health.protocolVersion == 1 else {
                throw LocalCoordinatorError.rejected("Coordinator protocol is not compatible")
            }
            coordinatorHealthMessage = "Coordinator reachable: \(health.service ?? "sync service")"
            lastError = nil
        } catch {
            coordinatorHealthMessage = "Coordinator unreachable"
            lastError = error.localizedDescription
        }
    }

    func refreshPendingSyncCount() {
        pendingSyncCount = (try? database.pendingOutboxCount()) ?? 0
    }

    private func canonicalSyncEvent(_ event: PendingSyncEvent) throws -> Any {
        let object = try JSONSerialization.jsonObject(with: Data(event.payloadJSON.utf8), options: [])
        guard let dictionary = object as? [String: Any] else { return object }
        if dictionary["eventId"] != nil, dictionary["type"] != nil, dictionary["payload"] != nil {
            return dictionary
        }
        let now = ISO8601DateFormatter().string(from: Date())
        return [
            "eventId": event.eventId.uuidString,
            "type": "legacy.\(event.deviceSequence)",
            "deviceId": session?.device.installationId ?? "60000000-0000-4000-8000-000000000001",
            "organizationId": session?.organization.id.uuidString ?? "20000000-0000-4000-8000-000000000001",
            "locationId": session?.shop?.id.uuidString ?? "21000000-0000-4000-8000-000000000001",
            "sequence": event.deviceSequence,
            "occurredAt": now,
            "payload": dictionary
        ]
    }
}

private struct LocalCoordinatorHealthResponse: Decodable {
    let ok: Bool
    let protocolVersion: Int
    let service: String?
}

private struct LocalCoordinatorPushResponse: Decodable {
    struct AcceptedEvent: Decodable {
        let eventId: UUID
        let status: String
    }

    let ok: Bool
    let accepted: [AcceptedEvent]
}

private enum LocalCoordinatorError: LocalizedError {
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .rejected(let message): message
        }
    }
}

struct CartDisplayLine: Identifiable, Equatable {
    var id: UUID { product.id }
    let product: StoreProduct
    let quantity: Quantity

    var total: Money {
        (try? product.unitPrice.multiplied(by: quantity)) ?? .mmk(0)
    }
}
