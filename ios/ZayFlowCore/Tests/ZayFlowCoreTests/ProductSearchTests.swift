import XCTest
@testable import ZayFlowCore

final class ProductSearchTests: XCTestCase {
    func testSearchMatchesWordsInAnyOrder() throws {
        let catalog = try DemoCatalog.loadFromBundle()
        let results = ProductSearch(products: catalog.products).search("tom yum noodle")

        XCTAssertEqual(results.first?.name, "Nom Nom Instant Noodle Tom Yum 120G")
    }

    func testSearchMatchesBarcodeExactly() throws {
        let catalog = try DemoCatalog.loadFromBundle()
        let product = ProductSearch(products: catalog.products).product(forBarcode: "ZF-DEMO-000010")

        XCTAssertEqual(product?.name, "Elan Detergent Powder Paris Perfume Scent 2.5KG")
    }

    func testSearchMatchesCategory() throws {
        let catalog = try DemoCatalog.loadFromBundle()
        let results = ProductSearch(products: catalog.products).search("household cleaning")

        XCTAssertTrue(results.count >= 3)
        XCTAssertTrue(results.allSatisfy { $0.category == "Household Cleaning" })
    }
}
