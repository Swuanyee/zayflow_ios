import XCTest
@testable import ZayFlowCore

final class QuantityTests: XCTestCase {
    func testParsesSixDecimalPlaces() throws {
        let quantity = try Quantity.parse("12.345678")

        XCTAssertEqual(quantity.microUnits, 12_345_678)
        XCTAssertEqual(quantity.decimalString, "12.345678")
    }

    func testAddsAndSubtracts() throws {
        let current = try Quantity.parse("10.5")
        let sold = try Quantity.parse("2.25")

        XCTAssertEqual(try current.subtracting(sold).decimalString, "8.25")
    }
}
