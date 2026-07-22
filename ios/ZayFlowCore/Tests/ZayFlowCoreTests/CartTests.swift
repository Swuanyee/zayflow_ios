import XCTest
@testable import ZayFlowCore

final class CartTests: XCTestCase {
    func testCartTotalsWithLineAndInvoiceDiscounts() throws {
        let catalog = try DemoCatalog.loadFromBundle()
        let noodles = catalog.products.first { $0.sku == "DEMO-NOODLE-001" }!
        let milk = catalog.products.first { $0.sku == "DEMO-MILK-001" }!
        let lines = [
            try CartLine(product: noodles, quantity: .units(2), discount: .percentage(basisPoints: 1_000)),
            try CartLine(product: milk, quantity: .units(1))
        ]
        let cart = Cart(lines: lines, invoiceDiscount: .fixed(.mmk(400)))

        let totals = try cart.totals()

        XCTAssertEqual(totals.subtotal.decimalString, "17800.00")
        XCTAssertEqual(totals.discountTotal.decimalString, "840.00")
        XCTAssertEqual(totals.grandTotal.decimalString, "16960.00")
    }

    func testAvailableStockSubtractsCurrentCartQuantity() throws {
        let catalog = try DemoCatalog.loadFromBundle()
        let eggs = catalog.products.first { $0.sku == "DEMO-EGGS-001" }!
        let cart = try Cart().adding(product: eggs, quantity: .units(3))

        let available = try cart.availableStock(productId: eggs.id, currentBalance: .units(10))

        XCTAssertEqual(available.decimalString, "7")
    }
}
