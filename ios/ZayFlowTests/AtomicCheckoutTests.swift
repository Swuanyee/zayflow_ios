import XCTest
import ZayFlowCore
@testable import ZayFlow

final class AtomicCheckoutTests: XCTestCase {
    func testCompletesSaleAndCommitsAllArtifactsAtomically() throws {
        let database = try AppDatabase.inMemory()
        let noodles = try XCTUnwrap(database.product(barcode: "ZF-DEMO-000002"))
        let milk = try XCTUnwrap(database.product(barcode: "ZF-DEMO-000006"))
        let initialNoodleStock = noodles.stockQuantity
        let initialMilkStock = milk.stockQuantity

        let sale = try database.completeSale(CheckoutRequest(
            lines: [
                CheckoutLine(productId: noodles.id, quantity: .units(2)),
                CheckoutLine(productId: milk.id, quantity: .units(1))
            ],
            paymentMethod: .cash,
            amountTendered: .mmk(20_000)
        ), now: Date(timeIntervalSince1970: 1_788_000_000))

        XCTAssertEqual(sale.grandTotal, .mmk(17_800))
        XCTAssertEqual(sale.change, .mmk(2_200))
        XCTAssertEqual(sale.receiptNumber, "ZF-DEMO-IPHN01-2026-00000001")
        XCTAssertEqual(try database.saleCount(), 1)
        XCTAssertEqual(try database.paymentCount(), 1)
        XCTAssertEqual(try database.auditEventCount(), 1)
        XCTAssertEqual(try database.outboxCount(), 1)
        XCTAssertEqual(try database.ledgerEntryCount(), 18)

        XCTAssertEqual(
            try database.product(barcode: "ZF-DEMO-000002")?.stockQuantity,
            try initialNoodleStock.subtracting(.units(2))
        )
        XCTAssertEqual(
            try database.product(barcode: "ZF-DEMO-000006")?.stockQuantity,
            try initialMilkStock.subtracting(.units(1))
        )

        let activity = try database.fetchSales()
        XCTAssertEqual(activity.first?.receiptNumber, sale.receiptNumber)
        XCTAssertEqual(activity.first?.itemCount, 3)
    }

    func testReceiptSequenceAdvancesWithoutCollision() throws {
        let database = try AppDatabase.inMemory()
        let product = try XCTUnwrap(database.product(barcode: "ZF-DEMO-000003"))
        let request = CheckoutRequest(
            lines: [CheckoutLine(productId: product.id, quantity: .units(1))],
            paymentMethod: .qr,
            amountTendered: product.unitPrice
        )

        let first = try database.completeSale(request)
        let second = try database.completeSale(request)

        XCTAssertTrue(first.receiptNumber.hasSuffix("00000001"))
        XCTAssertTrue(second.receiptNumber.hasSuffix("00000002"))
        XCTAssertEqual(try database.outboxCount(), 2)
    }

    func testInsufficientPaymentRollsBackEntireTransaction() throws {
        let database = try AppDatabase.inMemory()
        let product = try XCTUnwrap(database.product(barcode: "ZF-DEMO-000006"))
        let initialStock = product.stockQuantity

        XCTAssertThrowsError(try database.completeSale(CheckoutRequest(
            lines: [CheckoutLine(productId: product.id, quantity: .units(1))],
            paymentMethod: .cash,
            amountTendered: .mmk(1_000)
        ))) { error in
            XCTAssertEqual(error as? CheckoutError, .insufficientPayment(required: product.unitPrice))
        }

        XCTAssertEqual(try database.saleCount(), 0)
        XCTAssertEqual(try database.paymentCount(), 0)
        XCTAssertEqual(try database.outboxCount(), 0)
        XCTAssertEqual(try database.auditEventCount(), 0)
        XCTAssertEqual(try database.ledgerEntryCount(), 16)
        XCTAssertEqual(try database.product(barcode: "ZF-DEMO-000006")?.stockQuantity, initialStock)
    }

    func testInsufficientStockRollsBackEntireTransaction() throws {
        let database = try AppDatabase.inMemory()
        let rice = try XCTUnwrap(database.product(barcode: "ZF-DEMO-000001"))

        XCTAssertThrowsError(try database.completeSale(CheckoutRequest(
            lines: [CheckoutLine(productId: rice.id, quantity: .units(9))],
            paymentMethod: .cash,
            amountTendered: .mmk(1_000_000)
        )))

        XCTAssertEqual(try database.saleCount(), 0)
        XCTAssertEqual(try database.outboxCount(), 0)
        XCTAssertEqual(try database.ledgerEntryCount(), 16)
        XCTAssertEqual(try database.product(barcode: "ZF-DEMO-000001")?.stockQuantity, rice.stockQuantity)
    }

    func testCompletedSalePersistsAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("checkout.sqlite").path

        let first = try AppDatabase.atPath(path)
        let product = try XCTUnwrap(first.product(barcode: "ZF-DEMO-000004"))
        let completed = try first.completeSale(CheckoutRequest(
            lines: [CheckoutLine(productId: product.id, quantity: .units(1))],
            paymentMethod: .cash,
            amountTendered: .mmk(20_000)
        ))

        let reopened = try AppDatabase.atPath(path)
        XCTAssertEqual(try reopened.saleCount(), 1)
        XCTAssertEqual(try reopened.fetchSales().first?.receiptNumber, completed.receiptNumber)
        XCTAssertEqual(try reopened.outboxCount(), 1)
    }
}
