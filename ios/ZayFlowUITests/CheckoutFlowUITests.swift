import XCTest

final class CheckoutFlowUITests: XCTestCase {
    @MainActor
    func testCompletesCashSaleAndShowsItInActivity() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let product = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Ah May Htwar Peanut Oil 2L")
        ).firstMatch
        XCTAssertTrue(product.waitForExistence(timeout: 5))
        product.tap()

        let cart = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "View and edit cart")
        ).firstMatch
        XCTAssertTrue(cart.waitForExistence(timeout: 2))
        cart.tap()

        let charge = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Charge")
        ).firstMatch
        XCTAssertTrue(charge.waitForExistence(timeout: 2))
        charge.tap()

        XCTAssertTrue(app.navigationBars["Payment"].waitForExistence(timeout: 2))
        let completeSale = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete sale")
        ).firstMatch
        XCTAssertTrue(completeSale.isEnabled)
        completeSale.tap()

        XCTAssertTrue(app.staticTexts["Sale completed"].waitForExistence(timeout: 5))
        let receipt = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "ZF-DEMO-IPHN01-")
        ).firstMatch
        XCTAssertTrue(receipt.exists)
        let receiptNumber = receipt.label
        app.buttons["receipt-done"].tap()

        let cartDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["Current cart"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [cartDismissed], timeout: 3), .completed)
        app.tabBars.buttons["Activity"].tap()
        let activitySale = app.descendants(matching: .any)["activity-sale-row"].firstMatch
        guard activitySale.waitForExistence(timeout: 3) else {
            XCTFail("Completed sale did not appear in Activity")
            return
        }
        XCTAssertTrue(activitySale.label.contains(receiptNumber))
        XCTAssertTrue(activitySale.label.contains("26,300 Ks"))
    }
}
