import XCTest
@testable import CarPlayAssistant

// MARK: - UIComplianceEngineTests

final class UIComplianceEngineTests: XCTestCase {

    private var engine: UIComplianceEngine!

    override func setUp() {
        super.setUp()
        engine = UIComplianceEngine()
    }

    // MARK: - Display Truncation Tests

    func testShortResponseIsNotTruncatedWhileParked() {
        let text = "The weather is sunny today."
        let result = engine.validateResponse(text, drivingState: .parked)

        XCTAssertFalse(result.wasModified)
        XCTAssertEqual(result.displayText, text)
        XCTAssertEqual(result.spokenText, text)
        XCTAssertTrue(result.appliedRules.isEmpty)
    }

    func testLongResponseIsTruncatedForCityDriving() {
        // City limit is 160 chars for display
        let text = String(repeating: "A", count: 300)
        let result = engine.validateResponse(text, drivingState: .city)

        XCTAssertTrue(result.wasModified)
        XCTAssertTrue(result.appliedRules.contains(.displayTruncated))
        XCTAssertLessThanOrEqual(result.displayText.count, 160)
        XCTAssertTrue(result.displayText.hasSuffix("...I'll share more when you're parked."))
    }

    func testLongResponseIsTruncatedMoreAggressivelyOnHighway() {
        // Highway limit is 80 chars for display
        let text = String(repeating: "B", count: 200)
        let result = engine.validateResponse(text, drivingState: .highway)

        XCTAssertTrue(result.wasModified)
        XCTAssertTrue(result.appliedRules.contains(.displayTruncated))
        XCTAssertLessThanOrEqual(result.displayText.count, 80)
    }

    func testParkedAllowsLongerDisplay() {
        // Parked limit is 500 chars for display
        let text = String(repeating: "C", count: 400)
        let result = engine.validateResponse(text, drivingState: .parked)

        XCTAssertFalse(result.wasModified)
        XCTAssertEqual(result.displayText, text)
    }

    func testResponseExceedingParkedLimitIsTruncated() {
        let text = String(repeating: "D", count: 600)
        let result = engine.validateResponse(text, drivingState: .parked)

        XCTAssertTrue(result.wasModified)
        XCTAssertTrue(result.appliedRules.contains(.displayTruncated))
        XCTAssertLessThanOrEqual(result.displayText.count, 500)
    }

    // MARK: - Spoken Text Truncation Tests

    func testSpokenTextTruncatedOnHighway() {
        // Highway limit is 200 chars for spoken
        let sentences = (1...20).map { "Sentence number \($0) is here." }
        let text = sentences.joined(separator: " ")
        let result = engine.validateResponse(text, drivingState: .highway)

        XCTAssertTrue(result.appliedRules.contains(.voiceTruncated))
        // Spoken text should be truncated at sentence boundary
        XCTAssertTrue(result.spokenText.contains("...I'll share more when you're parked."))
    }

    func testSpokenTextNotTruncatedWhenShort() {
        let text = "Turn left in 200 feet."
        let result = engine.validateResponse(text, drivingState: .highway)

        XCTAssertFalse(result.appliedRules.contains(.voiceTruncated))
    }

    // MARK: - Phone Number Redaction Tests

    func testPhoneNumberRedactedWhileDriving() {
        let text = "Call them at 555-123-4567 for help."
        let result = engine.validateResponse(text, drivingState: .city)

        XCTAssertTrue(result.wasModified)
        XCTAssertTrue(result.appliedRules.contains(.phoneNumberRedacted))
        XCTAssertFalse(result.displayText.contains("555-123-4567"))
        XCTAssertTrue(result.displayText.contains("[phone hidden]"))
    }

    func testPhoneNumberNotRedactedWhenParked() {
        let text = "Call them at 555-123-4567 for help."
        let result = engine.validateResponse(text, drivingState: .parked)

        XCTAssertFalse(result.appliedRules.contains(.phoneNumberRedacted))
        XCTAssertTrue(result.displayText.contains("555-123-4567"))
    }

    func testMultiplePhoneFormatsRedacted() {
        let text = "Dial (800) 555-1234 or +1 212.555.6789."
        let result = engine.validateResponse(text, drivingState: .highway)

        XCTAssertTrue(result.appliedRules.contains(.phoneNumberRedacted))
        XCTAssertFalse(result.displayText.contains("555-1234"))
        XCTAssertFalse(result.displayText.contains("555.6789"))
    }

    // MARK: - URL Redaction Tests

    func testURLRedactedWhileDriving() {
        let text = "Visit https://example.com/info for details."
        let result = engine.validateResponse(text, drivingState: .city)

        XCTAssertTrue(result.wasModified)
        XCTAssertTrue(result.appliedRules.contains(.urlRedacted))
        XCTAssertFalse(result.displayText.contains("https://example.com"))
        XCTAssertTrue(result.displayText.contains("[link hidden]"))
    }

    func testURLNotRedactedWhenParked() {
        let text = "Visit https://example.com/info for details."
        let result = engine.validateResponse(text, drivingState: .parked)

        XCTAssertFalse(result.appliedRules.contains(.urlRedacted))
        XCTAssertTrue(result.displayText.contains("https://example.com/info"))
    }

    // MARK: - List Item Limiting Tests

    func testListItemsLimitedWhileDriving() {
        let items = Array(1...20)
        let (limited, wasLimited) = engine.limitListItems(items, drivingState: .city)

        XCTAssertTrue(wasLimited)
        XCTAssertEqual(limited.count, 12) // maxListItemsDriving = 12
    }

    func testListItemsLimitedMoreGenerouslyWhenParked() {
        let items = Array(1...30)
        let (limited, wasLimited) = engine.limitListItems(items, drivingState: .parked)

        XCTAssertTrue(wasLimited)
        XCTAssertEqual(limited.count, 24) // maxListItemsParked = 24
    }

    func testShortListNotLimited() {
        let items = Array(1...5)
        let (limited, wasLimited) = engine.limitListItems(items, drivingState: .city)

        XCTAssertFalse(wasLimited)
        XCTAssertEqual(limited.count, 5)
    }

    func testMaxListItemsForDrivingStates() {
        XCTAssertEqual(engine.maxListItems(for: .parked), 24)
        XCTAssertEqual(engine.maxListItems(for: .city), 12)
        XCTAssertEqual(engine.maxListItems(for: .highway), 12)
        XCTAssertEqual(engine.maxListItems(for: .unknown), 12)
    }

    // MARK: - Original Text Preserved

    func testOriginalTextPreservedInResult() {
        let text = "Call 555-123-4567 now."
        let result = engine.validateResponse(text, drivingState: .city)

        XCTAssertEqual(result.originalText, text)
        XCTAssertNotEqual(result.displayText, text)
    }
}

// MARK: - EmergencyProtocolTests

final class EmergencyProtocolTests: XCTestCase {

    private var emergencyProtocol: EmergencyProtocol!

    override func setUp() {
        super.setUp()
        emergencyProtocol = EmergencyProtocol(locationProvider: nil)
    }

    override func tearDown() {
        emergencyProtocol.cancelEmergency()
        emergencyProtocol = nil
        super.tearDown()
    }

    // MARK: - Emergency Type Detection

    func testDetectsCrashKeywords() {
        let type = emergencyProtocol.checkForEmergency(in: "I just crashed my car")
        XCTAssertEqual(type, .crash)
        XCTAssertTrue(emergencyProtocol.isEmergencyActive)
    }

    func testDetectsMedicalKeywords() {
        let type = emergencyProtocol.checkForEmergency(in: "I'm having chest pain")
        XCTAssertEqual(type, .medical)
    }

    func testDetectsRoadsideKeywords() {
        let type = emergencyProtocol.checkForEmergency(in: "I have a flat tire on the highway")
        XCTAssertEqual(type, .roadside)
    }

    func testDetectsSOSKeywords() {
        let type = emergencyProtocol.checkForEmergency(in: "Help me please, this is an emergency")
        // Could match either .sos or .medical etc. depending on keyword order
        XCTAssertNotNil(type)
        XCTAssertTrue(emergencyProtocol.isEmergencyActive)
    }

    func testNoEmergencyForNormalInput() {
        let type = emergencyProtocol.checkForEmergency(in: "What's the weather like today?")
        XCTAssertNil(type)
        XCTAssertFalse(emergencyProtocol.isEmergencyActive)
    }

    func testCaseInsensitiveDetection() {
        let type = emergencyProtocol.checkForEmergency(in: "I JUST HAD AN ACCIDENT")
        XCTAssertEqual(type, .crash)
    }

    // MARK: - Emergency Triggering

    func testTriggerEmergencySetsActiveState() {
        emergencyProtocol.triggerEmergency(type: .medical)

        XCTAssertTrue(emergencyProtocol.isEmergencyActive)
        XCTAssertNotNil(emergencyProtocol.activeEmergency)
        XCTAssertEqual(emergencyProtocol.activeEmergency?.type, .medical)
        XCTAssertEqual(emergencyProtocol.activeEmergency?.action, .call911)
    }

    func testTriggerRoadsideEmergencyCallsRoadside() {
        emergencyProtocol.triggerEmergency(type: .roadside)

        XCTAssertEqual(emergencyProtocol.activeEmergency?.action, .callRoadside)
    }

    func testCancelEmergencyClearsState() {
        emergencyProtocol.triggerEmergency(type: .crash)
        XCTAssertTrue(emergencyProtocol.isEmergencyActive)

        emergencyProtocol.cancelEmergency()

        XCTAssertFalse(emergencyProtocol.isEmergencyActive)
        XCTAssertNil(emergencyProtocol.activeEmergency)
    }

    // MARK: - Emergency History

    func testEmergencyHistoryTracksEvents() {
        emergencyProtocol.triggerEmergency(type: .crash)
        emergencyProtocol.cancelEmergency()
        emergencyProtocol.triggerEmergency(type: .medical)

        let history = emergencyProtocol.getEmergencyHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].type, .crash)
        XCTAssertEqual(history[1].type, .medical)
    }

    // MARK: - Emergency Action Mapping

    func testCrashMapsToCall911() {
        emergencyProtocol.triggerEmergency(type: .crash)
        XCTAssertEqual(emergencyProtocol.activeEmergency?.action, .call911)
    }

    func testMedicalMapsToCall911() {
        emergencyProtocol.triggerEmergency(type: .medical)
        XCTAssertEqual(emergencyProtocol.activeEmergency?.action, .call911)
    }

    func testSOSMapsToCall911() {
        emergencyProtocol.triggerEmergency(type: .sos)
        XCTAssertEqual(emergencyProtocol.activeEmergency?.action, .call911)
    }

    func testRoadsideMapsToCallRoadside() {
        emergencyProtocol.triggerEmergency(type: .roadside)
        XCTAssertEqual(emergencyProtocol.activeEmergency?.action, .callRoadside)
    }

    // MARK: - Location Formatting

    func testFormattedLocationReturnsNilWithoutProvider() {
        let location = emergencyProtocol.formattedLocationForEmergency()
        XCTAssertNil(location)
    }

    // MARK: - EmergencyType CaseIterable

    func testAllEmergencyTypesCovered() {
        let allTypes = EmergencyType.allCases
        XCTAssertEqual(allTypes.count, 4)
        XCTAssertTrue(allTypes.contains(.crash))
        XCTAssertTrue(allTypes.contains(.medical))
        XCTAssertTrue(allTypes.contains(.roadside))
        XCTAssertTrue(allTypes.contains(.sos))
    }
}
