import XCTest
@testable import ZayFlowCore

final class MoneyTests: XCTestCase {
    func testParsesAndFormatsMMK() throws {
        let money = try Money.parse("92500.00")

        XCTAssertEqual(money.minorUnits, 9_250_000)
        XCTAssertEqual(money.decimalString, "92500.00")
        XCTAssertEqual(money.displayString, "92,500 Ks")
    }

    func testAddsOnlyMatchingCurrencies() throws {
        let total = try Money.mmk(12_500).adding(.mmk(2_200))

        XCTAssertEqual(total.decimalString, "14700.00")
    }

    func testMultipliesByFractionalQuantityWithRounding() throws {
        let unitPrice = try Money.parse("12500.00")
        let quantity = try Quantity.parse("1.5")

        XCTAssertEqual(try unitPrice.multiplied(by: quantity).decimalString, "18750.00")
    }
}
