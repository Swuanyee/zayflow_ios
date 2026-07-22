import XCTest
import GRDB
import UIKit
@testable import ZayFlow

final class AppDatabaseTests: XCTestCase {
    func testFirstLaunchImportsDemoCatalogueAndOpeningStock() throws {
        let database = try AppDatabase.inMemory()

        XCTAssertEqual(try database.productCount(), 16)
        XCTAssertEqual(try database.ledgerEntryCount(), 16)

        let products = try database.fetchProducts()
        XCTAssertEqual(products.count, 16)
        XCTAssertTrue(products.allSatisfy { $0.stockQuantity.microUnits > 0 })
    }

    func testBarcodeLookupUsesPersistedCatalogue() throws {
        let database = try AppDatabase.inMemory()

        let product = try database.product(barcode: "ZF-DEMO-000010")

        XCTAssertEqual(product?.sku, "DEMO-DETERGENT-001")
    }

    func testCurrentCityMallDemoProductsHaveBundledArtwork() throws {
        let products = try AppDatabase.inMemory().fetchProducts()
        let productsWithArtwork = Set(products.compactMap { product in
            UIImage(named: "Product-\(product.sku)") == nil ? nil : product.sku
        })

        XCTAssertEqual(productsWithArtwork.count, 15)
        XCTAssertFalse(productsWithArtwork.contains("DEMO-EGGS-001"))
    }

    func testDemoImportIsIdempotentAcrossDatabaseRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("zayflow.sqlite").path

        let first = try AppDatabase.atPath(path)
        XCTAssertEqual(try first.productCount(), 16)

        let reopened = try AppDatabase.atPath(path)
        XCTAssertEqual(try reopened.productCount(), 16)
        XCTAssertEqual(try reopened.ledgerEntryCount(), 16)
    }

    func testDatabaseIsEncryptedAtRestAndRejectsMissingKey() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("encrypted.sqlite").path

        let database = try AppDatabase.atPath(path)
        XCTAssertEqual(try database.productCount(), 16)

        let header = try Data(contentsOf: URL(fileURLWithPath: path)).prefix(16)
        XCTAssertNotEqual(String(data: header, encoding: .utf8), "SQLite format 3\0")

        XCTAssertThrowsError(try DatabaseQueue(path: path))
    }
}
