import XCTest
@testable import ZayFlowCore

final class StockLedgerTests: XCTestCase {
    func testProjectsBalanceFromAppendOnlyLedger() throws {
        let productId = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let entries = [
            StockLedgerEntry(
                id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
                productId: productId,
                movementType: .openingStock,
                quantityDelta: .units(100),
                occurredAt: Date(timeIntervalSince1970: 1)
            ),
            StockLedgerEntry(
                id: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
                productId: productId,
                movementType: .sale,
                quantityDelta: try Quantity.parse("-2"),
                occurredAt: Date(timeIntervalSince1970: 2)
            ),
            StockLedgerEntry(
                id: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
                productId: productId,
                movementType: .stockAdjustment,
                quantityDelta: try Quantity.parse("5"),
                occurredAt: Date(timeIntervalSince1970: 3)
            )
        ]

        let balance = try StockBalanceProjector().balance(for: productId, entries: entries)

        XCTAssertEqual(balance.decimalString, "103")
    }
}
