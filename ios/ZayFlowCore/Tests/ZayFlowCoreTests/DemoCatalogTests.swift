import XCTest
@testable import ZayFlowCore

final class DemoCatalogTests: XCTestCase {
    func testLoadsBundledDemoCatalogue() throws {
        let catalog = try DemoCatalog.loadFromBundle()

        XCTAssertEqual(catalog.products.count, 16)
        XCTAssertTrue(catalog.products.allSatisfy { !$0.name.isEmpty })
        XCTAssertTrue(catalog.products.allSatisfy { $0.unitPrice.currency == "MMK" })
        XCTAssertTrue(catalog.products.flatMap(\.barcodes).allSatisfy { $0.barcode.hasPrefix("ZF-DEMO-") })
    }

    func testIncludesExpectedCityMallInspiredProducts() throws {
        let catalog = try DemoCatalog.loadFromBundle()
        let names = Set(catalog.products.map(\.name))

        XCTAssertTrue(names.contains("Nom Nom Instant Noodle Tom Yum 120G"))
        XCTAssertTrue(names.contains("Elan Detergent Powder Paris Perfume Scent 2.5KG"))
        XCTAssertTrue(names.contains("Baby Angel Diaper Pant 2XL 50 Pieces"))
    }
}
