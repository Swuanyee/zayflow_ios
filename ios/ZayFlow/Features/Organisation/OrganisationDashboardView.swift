import SwiftUI
import ZayFlowCore

struct OrganisationDashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: OrganisationTab = .overview
    @State private var selectedShopID: UUID?
    @State private var showSignOutConfirmation = false
    @State private var showAddShop = false
    @State private var showAddItem = false
    @State private var showAddUser = false
    @State private var editingDevice: OrganisationDevice?

    private var snapshot: OrganisationSnapshot? { model.organisationSnapshot }
    private var canManage: Bool { model.session?.user.role == .owner || model.session?.user.role == .admin }

    var body: some View {
        Group {
            if let session = model.session, let snapshot {
                if horizontalSizeClass == .regular {
                    NavigationSplitView {
                        sidebar(session: session, snapshot: snapshot)
                    } detail: {
                        NavigationStack { content(session: session, snapshot: snapshot) }
                    }
                } else {
                    TabView(selection: $selectedTab) {
                        ForEach(OrganisationTab.visibleTabs(canManageUsers: canManage)) { tab in
                            NavigationStack { content(session: session, snapshot: snapshot, forcedTab: tab) }
                                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                                .tag(tab)
                        }
                    }
                }
            } else {
                ProgressView("Loading organisation")
                    .task { model.loadOrganisationData() }
            }
        }
        .sheet(isPresented: $showAddShop) { AddShopSheet() }
        .sheet(isPresented: $showAddItem) { AddCatalogItemSheet(snapshot: snapshot) }
        .sheet(isPresented: $showAddUser) { AddUserSheet(snapshot: snapshot) }
        .sheet(item: $editingDevice) { device in
            DeviceRestrictionsSheet(device: device, categories: Array(Set(snapshot?.catalog.map(\.category) ?? [])).sorted())
        }
        .confirmationDialog("Sign out of ZayFlow?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { model.signOut() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { model.loadOrganisationData() }
    }

    private func sidebar(session: AuthSession, snapshot: OrganisationSnapshot) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Image("ZayFlowLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Organisation")
                    .font(.title3.bold())
                Text("\(session.user.displayName) · \(session.user.role.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)

            List {
                ForEach(OrganisationTab.visibleTabs(canManageUsers: canManage)) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .font(.body.weight(selectedTab == tab ? .bold : .regular))
                            .foregroundStyle(selectedTab == tab ? ZayFlowTheme.brand : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 10) {
                SyncDueView(session: session)
                Button { model.requestPOSMode() } label: {
                    Label("Switch to POS", systemImage: "cart.fill")
                }
                Button(role: .destructive) { showSignOutConfirmation = true } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .font(.callout.weight(.semibold))
            .padding(16)
        }
        .navigationSplitViewColumnWidth(min: 230, ideal: 260)
    }

    @ViewBuilder
    private func content(session: AuthSession, snapshot: OrganisationSnapshot, forcedTab: OrganisationTab? = nil) -> some View {
        let tab = forcedTab ?? selectedTab
        Group {
            switch tab {
            case .overview:
                OverviewPage(snapshot: filtered(snapshot), selectedShopID: $selectedShopID, openPOS: { model.requestPOSMode() })
            case .shops:
                ShopsPage(snapshot: snapshot, canManage: canManage, addAction: { showAddShop = true })
            case .catalog:
                CatalogPage(snapshot: filtered(snapshot), canManage: canManage, addAction: { showAddItem = true })
            case .inventory:
                InventoryPage(snapshot: filtered(snapshot), selectedShopID: $selectedShopID)
            case .devices:
                DevicesPage(snapshot: filtered(snapshot), canManage: canManage) { device in editingDevice = device }
            case .users:
                UsersPage(snapshot: snapshot, canManage: canManage, addAction: { showAddUser = true })
            }
        }
        .navigationTitle(tab.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if horizontalSizeClass != .regular {
                    Button { model.requestPOSMode() } label: { Label("Open POS", systemImage: "cart.fill") }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Text(session.user.displayName)
                    Text(session.organization.name)
                    Divider()
                    Button("Refresh") { model.loadOrganisationData() }
                    Button("Sign Out", role: .destructive) { showSignOutConfirmation = true }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if canManage {
                    switch tab {
                    case .shops:
                        Button { showAddShop = true } label: { Label("Add Shop", systemImage: "plus") }
                    case .catalog:
                        Button { showAddItem = true } label: { Label("Add Item", systemImage: "plus") }
                    case .users:
                        Button { showAddUser = true } label: { Label("Add User", systemImage: "plus") }
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if session.isSyncOverdue {
                SyncDueView(session: session).padding(.horizontal).padding(.top, 6)
            }
        }
    }

    private func filtered(_ snapshot: OrganisationSnapshot) -> OrganisationSnapshot {
        guard let selectedShopID else { return snapshot }
        guard let shop = snapshot.shops.first(where: { $0.id == selectedShopID }) else { return snapshot }
        return OrganisationSnapshot(
            shops: [shop],
            users: snapshot.users,
            devices: snapshot.devices.filter { $0.shopCode == nil || $0.shopCode == shop.code },
            catalog: snapshot.catalog.filter { $0.assignedShopCodes.contains(shop.code) },
            inventory: snapshot.inventory.filter { $0.shop.id == selectedShopID },
            dailyMetrics: snapshot.dailyMetrics.filter { $0.shopCode == shop.code }
        )
    }
}

private enum OrganisationTab: String, Identifiable, CaseIterable {
    case overview
    case shops
    case catalog
    case inventory
    case devices
    case users

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .overview: "chart.line.uptrend.xyaxis"
        case .shops: "building.2.fill"
        case .catalog: "square.grid.2x2.fill"
        case .inventory: "shippingbox.fill"
        case .devices: "iphone.gen3"
        case .users: "person.2.fill"
        }
    }

    static func visibleTabs(canManageUsers: Bool) -> [OrganisationTab] {
        canManageUsers ? allCases : [.overview, .shops, .catalog, .inventory, .devices]
    }
}

private struct SyncDueView: View {
    let session: AuthSession

    var body: some View {
        Label(session.isSyncOverdue ? "Read-only until full sync" : "Offline ready · sync by \(session.device.requiresFullSyncBy.formatted(date: .abbreviated, time: .omitted))", systemImage: session.isSyncOverdue ? "exclamationmark.triangle.fill" : "checkmark.icloud.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(session.isSyncOverdue ? ZayFlowTheme.warning : ZayFlowTheme.brand)
            .padding(10)
            .background((session.isSyncOverdue ? ZayFlowTheme.warning : ZayFlowTheme.brand).opacity(0.12), in: Capsule())
    }
}

private struct OverviewPage: View {
    let snapshot: OrganisationSnapshot
    @Binding var selectedShopID: UUID?
    let openPOS: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SurfaceCard {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(ZayFlowTheme.brand.opacity(0.14))
                            Image(systemName: "cart.fill")
                                .foregroundStyle(ZayFlowTheme.brand)
                        }
                        .frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ready to sell")
                                .font(.headline)
                            Text("Open the POS register for one of your assigned shops.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: openPOS) {
                            Label("Open POS", systemImage: "arrow.right.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                ShopScopePicker(shops: snapshot.shops, selectedShopID: $selectedShopID)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                    MetricCard(title: "Revenue", value: snapshot.overview.revenue.displayString, symbol: "banknote.fill", tint: ZayFlowTheme.brand)
                    MetricCard(title: "Gross profit", value: snapshot.overview.grossProfit.displayString, subtitle: snapshot.overview.grossMarginText, symbol: "chart.pie.fill", tint: .blue)
                    MetricCard(title: "Inventory value", value: snapshot.overview.inventoryValue.displayString, symbol: "cube.box.fill", tint: .indigo)
                    MetricCard(title: "Low stock", value: "\(snapshot.overview.lowStockCount)", symbol: "exclamationmark.triangle.fill", tint: ZayFlowTheme.warning)
                }
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("90-day revenue trend")
                            .font(.headline)
                        BarTrend(metrics: snapshot.dailyMetrics)
                            .frame(height: 150)
                    }
                }
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Shop comparison")
                            .font(.headline)
                        ForEach(shopTotals, id: \.0) { code, total in
                            HStack {
                                Text(code).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(total.displayString).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Low-stock priorities")
                            .font(.headline)
                        ForEach(snapshot.inventory.filter(\.isLowStock).prefix(6)) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.productName).font(.subheadline.weight(.semibold))
                                    Text("\(item.shop.code) · threshold \(item.lowStockThreshold.decimalString)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.quantity.decimalString)
                                    .foregroundStyle(ZayFlowTheme.warning)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var shopTotals: [(String, Money)] {
        let grouped = Dictionary(grouping: snapshot.dailyMetrics, by: \.shopCode)
        return grouped.map { code, metrics in
            let total = metrics.reduce(Int64(0)) { $0 + $1.revenue.minorUnits }
            return (code, (try? Money(minorUnits: total, currency: "MMK")) ?? .mmk(0))
        }
        .sorted { $0.1.minorUnits > $1.1.minorUnits }
    }
}

private struct ShopsPage: View {
    let snapshot: OrganisationSnapshot
    let canManage: Bool
    let addAction: () -> Void
    @State private var search = ""

    var body: some View {
        List {
            if canManage {
                Button(action: addAction) { Label("Add new shop", systemImage: "plus.circle.fill") }
            }
            ForEach(filtered) { shop in
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shop.name).font(.headline)
                                Text("\(shop.code) · \(shop.city)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(text: shop.status.capitalized, color: ZayFlowTheme.brand)
                        }
                        HStack {
                            MiniStat("Items", "\(shop.itemCount)")
                            MiniStat("Low", "\(shop.lowStockCount)")
                            MiniStat("Users", "\(shop.userCount)")
                            MiniStat("Value", shop.inventoryValue.displayString)
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "Search shops")
    }

    private var filtered: [OrganisationShop] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return snapshot.shops }
        return snapshot.shops.filter { [ $0.name, $0.code, $0.city ].joined(separator: " ").lowercased().contains(query) }
    }
}

private struct CatalogPage: View {
    let snapshot: OrganisationSnapshot
    let canManage: Bool
    let addAction: () -> Void
    @State private var search = ""

    var body: some View {
        List {
            if canManage {
                Button(action: addAction) { Label("Add catalog item", systemImage: "plus.circle.fill") }
            }
            ForEach(filtered) { item in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(ZayFlowTheme.categoryColor(item.category).opacity(0.12))
                        Image(systemName: ZayFlowTheme.categorySymbol(item.category)).foregroundStyle(ZayFlowTheme.categoryColor(item.category))
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.headline)
                        Text("\(item.sku) · \(item.category)").font(.caption).foregroundStyle(.secondary)
                        Text(item.assignedShopCodes.isEmpty ? "Not assigned" : item.assignedShopCodes.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(item.unitPrice.displayString).font(.subheadline.weight(.semibold))
                        Text("Cost \(item.unitCost.displayString)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search catalog")
    }

    private var filtered: [OrganisationCatalogItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return snapshot.catalog }
        return snapshot.catalog.filter { [ $0.name, $0.sku, $0.category, $0.assignedShopCodes.joined(separator: " ") ].joined(separator: " ").lowercased().contains(query) }
    }
}

private struct InventoryPage: View {
    @Environment(AppModel.self) private var model
    let snapshot: OrganisationSnapshot
    @Binding var selectedShopID: UUID?
    @State private var search = ""

    var body: some View {
        List {
            Section { ShopScopePicker(shops: snapshot.shops, selectedShopID: $selectedShopID) }
            ForEach(filtered) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.productName).font(.headline)
                            Text("\(item.shop.code) · \(item.sku) · \(item.category)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(text: item.isLowStock ? "Low" : "OK", color: item.isLowStock ? ZayFlowTheme.warning : ZayFlowTheme.brand)
                    }
                    HStack {
                        MiniStat("On hand", item.quantity.decimalString)
                        MiniStat("Threshold", item.lowStockThreshold.decimalString)
                        MiniStat("Value", item.value.displayString)
                    }
                    HStack {
                        Button("Receive +5") { model.adjustOrganisationInventory(shopID: item.shop.id, productID: item.productId, deltaUnits: 5, reason: "Quick receive") }
                        Button("Adjust -1") { model.adjustOrganisationInventory(shopID: item.shop.id, productID: item.productId, deltaUnits: -1, reason: "Quick adjustment") }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .searchable(text: $search, prompt: "Search inventory")
    }

    private var filtered: [OrganisationInventoryItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return snapshot.inventory }
        return snapshot.inventory.filter { [ $0.productName, $0.sku, $0.category, $0.shop.code ].joined(separator: " ").lowercased().contains(query) }
    }
}

private struct UsersPage: View {
    let snapshot: OrganisationSnapshot
    let canManage: Bool
    let addAction: () -> Void

    var body: some View {
        List {
            if canManage {
                Button(action: addAction) { Label("Add user", systemImage: "person.badge.plus") }
            }
            ForEach(snapshot.users) { user in
                HStack {
                    Image(systemName: user.role == .cashier ? "person.fill" : "person.crop.circle.badge.checkmark")
                        .foregroundStyle(ZayFlowTheme.brand)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName).font(.headline)
                        Text("\(user.userCode) · \(user.role.rawValue.capitalized)").font(.caption).foregroundStyle(.secondary)
                        Text(user.shopCodes.isEmpty ? "All shops" : user.shopCodes.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        if user.canSell { StatusBadge(text: "Sell", color: .blue) }
                        if user.canIntake { StatusBadge(text: "Intake", color: .indigo) }
                    }
                }
            }
        }
    }
}

private struct DevicesPage: View {
    let snapshot: OrganisationSnapshot
    let canManage: Bool
    let editAction: (OrganisationDevice) -> Void

    var body: some View {
        List {
            Section {
                Text("Restrict a physical POS to specific item categories. Devices with no selected categories remain unrestricted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.devices) { device in
                HStack(spacing: 12) {
                    Image(systemName: device.platform == "ios" ? "iphone.gen3" : "desktopcomputer")
                        .font(.title3)
                        .foregroundStyle(ZayFlowTheme.brand)
                        .frame(width: 42, height: 42)
                        .background(ZayFlowTheme.mintSurface, in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.label).font(.headline)
                        Text([device.platform.uppercased(), device.shopCode].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(device.isUnrestricted ? "Unrestricted categories" : device.allowedCategories.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(device.isUnrestricted ? .secondary : ZayFlowTheme.brand)
                    }
                    Spacer()
                    if canManage {
                        Button("Edit") { editAction(device) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 6)
            }
            if snapshot.devices.isEmpty {
                ContentUnavailableView("No POS devices", systemImage: "iphone.slash", description: Text("Sign in on a POS device to register it here."))
            }
        }
    }
}

private struct AddShopSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var city = "Yangon"
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Shop ID", text: $code).textInputAutocapitalization(.characters)
                TextField("Name", text: $name)
                TextField("City", text: $city)
                TextField("Address", text: $address)
            }
            .navigationTitle("Add Shop")
            .toolbar {
                Button("Cancel") { dismiss() }
                Button("Save") {
                    model.addOrganisationShop(code: code, name: name, city: city, address: address.isEmpty ? nil : address)
                    if model.lastError == nil { dismiss() }
                }
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct AddCatalogItemSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let snapshot: OrganisationSnapshot?
    @State private var name = ""
    @State private var sku = ""
    @State private var category = "Private Items"
    @State private var price = "2500"
    @State private var cost = "1800"
    @State private var openingStock = "12"
    @State private var selectedShopIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                    TextField("SKU", text: $sku).textInputAutocapitalization(.characters)
                    TextField("Category", text: $category)
                }
                Section("Pricing") {
                    TextField("Selling price", text: $price).keyboardType(.numberPad)
                    TextField("Cost", text: $cost).keyboardType(.numberPad)
                    TextField("Opening stock", text: $openingStock).keyboardType(.numberPad)
                }
                Section("Assign to shops") {
                    ForEach(snapshot?.shops ?? []) { shop in
                        Toggle("\(shop.name) (\(shop.code))", isOn: Binding(
                            get: { selectedShopIDs.contains(shop.id) },
                            set: { value in
                                if value { selectedShopIDs.insert(shop.id) } else { selectedShopIDs.remove(shop.id) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                Button("Cancel") { dismiss() }
                Button("Save") {
                    model.addOrganisationCatalogItem(
                        name: name,
                        sku: sku,
                        category: category,
                        priceMajor: Int64(price) ?? 0,
                        costMajor: Int64(cost) ?? 0,
                        shopIDs: Array(selectedShopIDs),
                        openingStock: Int64(openingStock) ?? 0
                    )
                    if model.lastError == nil { dismiss() }
                }
                .disabled(name.isEmpty || sku.isEmpty || selectedShopIDs.isEmpty)
            }
        }
    }
}

private struct AddUserSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let snapshot: OrganisationSnapshot?
    @State private var userCode = ""
    @State private var displayName = ""
    @State private var password = "demo"
    @State private var role: UserRole = .cashier
    @State private var canSell = true
    @State private var canIntake = false
    @State private var selectedShopIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("User ID", text: $userCode).textInputAutocapitalization(.characters)
                TextField("Display name", text: $displayName)
                SecureField("Temporary password", text: $password)
                Picker("Role", selection: $role) {
                    ForEach(UserRole.organisationCases, id: \.rawValue) { role in
                        Text(role.rawValue.capitalized).tag(role)
                    }
                }
                Toggle("Can sell", isOn: $canSell)
                Toggle("Can intake", isOn: $canIntake)
                Section("Assigned shops") {
                    ForEach(snapshot?.shops ?? []) { shop in
                        Toggle("\(shop.name) (\(shop.code))", isOn: Binding(
                            get: { selectedShopIDs.contains(shop.id) },
                            set: { value in
                                if value { selectedShopIDs.insert(shop.id) } else { selectedShopIDs.remove(shop.id) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Add User")
            .toolbar {
                Button("Cancel") { dismiss() }
                Button("Save") {
                    model.addOrganisationUser(userCode: userCode, displayName: displayName, role: role, password: password, shopIDs: Array(selectedShopIDs), canSell: canSell, canIntake: canIntake)
                    if model.lastError == nil { dismiss() }
                }
                .disabled(userCode.isEmpty || displayName.isEmpty || password.isEmpty || ((role == .manager || role == .cashier) && selectedShopIDs.isEmpty))
            }
        }
    }
}

private struct DeviceRestrictionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let device: OrganisationDevice
    let categories: [String]
    @State private var unrestricted: Bool
    @State private var selectedCategories: Set<String>

    init(device: OrganisationDevice, categories: [String]) {
        self.device = device
        self.categories = categories
        _unrestricted = State(initialValue: device.allowedCategories.isEmpty)
        _selectedCategories = State(initialValue: Set(device.allowedCategories))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    LabeledContent("Name", value: device.label)
                    LabeledContent("Platform", value: device.platform.uppercased())
                    LabeledContent("Shop", value: device.shopCode ?? "Not assigned")
                }
                Section("Category access") {
                    Toggle("Unrestricted", isOn: $unrestricted)
                    if unrestricted {
                        Text("This POS can sell every item enabled for its shop.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(categories, id: \.self) { category in
                            Toggle(category, isOn: Binding(
                                get: { selectedCategories.contains(category) },
                                set: { value in
                                    if value { selectedCategories.insert(category) } else { selectedCategories.remove(category) }
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("Device Access")
            .toolbar {
                Button("Cancel") { dismiss() }
                Button("Save") {
                    model.updateDeviceCategoryRestrictions(deviceID: device.id, categories: unrestricted ? [] : selectedCategories)
                    if model.lastError == nil { dismiss() }
                }
                .disabled(!unrestricted && selectedCategories.isEmpty)
            }
        }
    }
}

private struct ShopScopePicker: View {
    let shops: [OrganisationShop]
    @Binding var selectedShopID: UUID?

    var body: some View {
        Picker("Shop", selection: $selectedShopID) {
            Text("All shops").tag(nil as UUID?)
            ForEach(shops) { shop in
                Text(shop.code).tag(shop.id as UUID?)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let symbol: String
    let tint: Color

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
                if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct BarTrend: View {
    let metrics: [OrganisationDailyMetric]

    private var totals: [Int64] {
        Dictionary(grouping: metrics, by: \.date)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.revenue.minorUnits } }
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(totals.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(totals.suffix(45).enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ZayFlowTheme.brand.gradient)
                        .frame(height: max(4, proxy.size.height * CGFloat(Double(value) / Double(maxValue))))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityLabel("Revenue trend for the last ninety days")
    }
}

private struct MiniStat: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.caption.weight(.bold))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

private extension UserRole {
    static var organisationCases: [UserRole] { [.owner, .admin, .manager, .cashier] }
}
