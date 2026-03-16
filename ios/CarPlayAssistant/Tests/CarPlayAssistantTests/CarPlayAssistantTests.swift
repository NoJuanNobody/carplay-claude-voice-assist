import XCTest
@testable import CarPlayAssistant

final class CarPlayAssistantTests: XCTestCase {
    func testVersion() {
        let assistant = CarPlayAssistant()
        XCTAssertEqual(assistant.version, "0.1.0")
    }

    func testUserProfileCreation() {
        let profile = UserProfile()
        XCTAssertNotNil(profile.id)
    }
}
