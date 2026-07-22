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

    var selectedSection: Section = .sell
    var products: [StoreProduct] = []
    var searchText = ""
    var selectedCategory = "All"
    var productSort: ProductSort = .name
    var cartLines: [CartDisplayLine] = []
    var sales: [SaleSummary] = []
    var isCartPresented = false
    var lastError: String?

    init(database: AppDatabase) throws {
        self.database = database
        products = try database.fetchProducts()
        sales = try database.fetchSales()
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
        let request = CheckoutRequest(
            lines: cartLines.map { CheckoutLine(productId: $0.product.id, quantity: $0.quantity) },
            paymentMethod: paymentMethod,
            amountTendered: amountTendered
        )
        let completed = try database.completeSale(request)
        cartLines.removeAll()
        products = try database.fetchProducts()
        sales = try database.fetchSales()
        return completed
    }

    func reloadProducts() {
        do {
            products = try database.fetchProducts()
            sales = try database.fetchSales()
        } catch {
            lastError = error.localizedDescription
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
