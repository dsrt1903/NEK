import XCTest

final class NEKUITests: XCTestCase {
    @MainActor
    func testBookingAppearsInBothRoles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let client = app.buttons["Клиент"]
        XCTAssertTrue(client.waitForExistence(timeout: 10))
        capture("01-login")
        pause(4)
        client.tap()

        let slot = app.buttons.matching(identifier: "availableSlot").firstMatch
        XCTAssertTrue(slot.waitForExistence(timeout: 15))
        capture("02-booking")
        pause(5)
        slot.tap()

        let submit = app.buttons["Подтвердить запись"]
        if !submit.isHittable { app.swipeUp() }
        XCTAssertTrue(submit.isHittable)
        submit.tap()
        let success = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Запись подтверждена")).firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: 10))
        pause(5)

        app.tabBars.buttons["Мои визиты"].tap()
        let visit = app.staticTexts["Консультация"]
        XCTAssertTrue(visit.waitForExistence(timeout: 10))
        capture("03-client-visits")
        pause(6)
        app.buttons["Выйти"].tap()

        let admin = app.buttons["Администратор"]
        XCTAssertTrue(admin.waitForExistence(timeout: 10))
        admin.tap()
        XCTAssertTrue(app.staticTexts["Календарь студии"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Милана"].waitForExistence(timeout: 10))
        capture("04-studio-calendar")
        pause(7)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        let interval = expectation(description: "Пауза для демонстрации")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { interval.fulfill() }
        wait(for: [interval], timeout: seconds + 2)
    }
}
