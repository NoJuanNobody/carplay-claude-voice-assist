import XCTest
@testable import CarPlayAssistant

// MARK: - LocalResponseEngineTests

final class LocalResponseEngineTests: XCTestCase {

    private var engine: LocalResponseEngine!

    override func setUp() {
        super.setUp()
        engine = LocalResponseEngine()
    }

    // MARK: - Time Query Tests

    func testHandlesTimeQuery() {
        let response = engine.processOffline("What time is it?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .time)
        XCTAssertEqual(response?.confidence, 0.95)
        XCTAssertTrue(response!.text.contains("current time"))
    }

    func testHandlesDateQuery() {
        let response = engine.processOffline("What's today's date?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .time)
        XCTAssertTrue(response!.text.starts(with: "It's"))
    }

    func testHandlesVariousTimePhrasings() {
        let queries = [
            "what time is it",
            "tell me the time",
            "what's the time",
            "current time",
            "what hour is it"
        ]

        for query in queries {
            let response = engine.processOffline(query)
            XCTAssertNotNil(response, "Expected response for query: '\(query)'")
            XCTAssertEqual(response?.category, .time, "Expected .time category for query: '\(query)'")
        }
    }

    // MARK: - Math Query Tests

    func testHandlesAddition() {
        let response = engine.processOffline("What is 5 plus 3?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .math)
        XCTAssertEqual(response?.confidence, 0.99)
        XCTAssertTrue(response!.text.contains("8"))
    }

    func testHandlesSubtraction() {
        let response = engine.processOffline("What is 10 minus 4?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .math)
        XCTAssertTrue(response!.text.contains("6"))
    }

    func testHandlesMultiplication() {
        let response = engine.processOffline("What is 7 times 6?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .math)
        XCTAssertTrue(response!.text.contains("42"))
    }

    func testHandlesDivision() {
        let response = engine.processOffline("What is 20 divided by 4?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .math)
        XCTAssertTrue(response!.text.contains("5"))
    }

    func testHandlesDivisionByZero() {
        let response = engine.processOffline("What is 10 divided by 0?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .math)
        XCTAssertTrue(response!.text.contains("can't divide by zero"))
    }

    func testHandlesDecimalMath() {
        let response = engine.processOffline("What is 3.5 plus 2.5?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .math)
        XCTAssertTrue(response!.text.contains("6"))
    }

    // MARK: - Unit Conversion Tests

    func testHandlesFahrenheitToCelsius() {
        let response = engine.processOffline("Convert 100 fahrenheit to celsius")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .unitConversion)
        XCTAssertEqual(response?.confidence, 0.9)
        // 100F = 37.78C
        XCTAssertTrue(response!.text.contains("37.78"))
    }

    func testHandlesCelsiusToFahrenheit() {
        let response = engine.processOffline("Convert 0 celsius to fahrenheit")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .unitConversion)
        XCTAssertTrue(response!.text.contains("32"))
    }

    func testHandlesMilesToKilometers() {
        let response = engine.processOffline("Convert 10 miles to kilometers")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .unitConversion)
        XCTAssertTrue(response!.text.contains("16.09"))
    }

    func testHandlesKilometersToMiles() {
        let response = engine.processOffline("Convert 100 km to miles")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .unitConversion)
        XCTAssertTrue(response!.text.contains("62.14"))
    }

    func testHandlesPoundsToKilograms() {
        let response = engine.processOffline("Convert 150 pounds to kilograms")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .unitConversion)
        XCTAssertTrue(response!.text.contains("68.04"))
    }

    func testHandlesMphToKph() {
        let response = engine.processOffline("Convert 60 mph to km/h")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .unitConversion)
        XCTAssertTrue(response!.text.contains("96.56"))
    }

    // MARK: - Preference Query Tests

    func testReturnsStoredPreference() {
        engine.storePreference(key: "home_address", value: "123 Main St")

        let response = engine.processOffline("What is my home address?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .preferences)
        XCTAssertTrue(response!.text.contains("123 Main St"))
    }

    func testReturnsNotFoundForMissingPreference() {
        let response = engine.processOffline("What is my home address?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .preferences)
        XCTAssertTrue(response!.text.contains("don't have"))
    }

    func testLoadPreferencesFromDictionary() {
        engine.loadPreferences([
            "home_address": "456 Oak Ave",
            "user_name": "Alice"
        ])

        let homeResponse = engine.processOffline("What's my home address?")
        XCTAssertNotNil(homeResponse)
        XCTAssertTrue(homeResponse!.text.contains("456 Oak Ave"))

        let nameResponse = engine.processOffline("What's my name?")
        XCTAssertNotNil(nameResponse)
        XCTAssertTrue(nameResponse!.text.contains("Alice"))
    }

    func testGetPreference() {
        engine.storePreference(key: "favorite_station", value: "KQED")

        XCTAssertEqual(engine.getPreference(key: "favorite_station"), "KQED")
        XCTAssertNil(engine.getPreference(key: "nonexistent"))
    }

    // MARK: - Unrecognized Query Tests

    func testReturnsNilForUnrecognizedQuery() {
        let response = engine.processOffline("Tell me about the history of Rome")

        XCTAssertNil(response)
    }

    func testReturnsNilForEmptyInput() {
        let response = engine.processOffline("")

        XCTAssertNil(response)
    }

    // MARK: - Case Insensitivity Tests

    func testCaseInsensitiveTimeQuery() {
        let response = engine.processOffline("WHAT TIME IS IT?")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .time)
    }

    func testCaseInsensitiveMathQuery() {
        let response = engine.processOffline("CALCULATE 5 PLUS 3")

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.category, .math)
    }
}

// MARK: - OfflineCacheManagerTests

final class OfflineCacheManagerTests: XCTestCase {

    private var cacheManager: OfflineCacheManager!
    private let testDirectoryName = "TestOfflineCache_\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        cacheManager = OfflineCacheManager(directoryName: testDirectoryName, ttl: 3600) // 1 hour TTL
    }

    override func tearDown() {
        cacheManager.clearCache()
        // Clean up test directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let testDir = documentsURL.appendingPathComponent(testDirectoryName)
        try? FileManager.default.removeItem(at: testDir)
        cacheManager = nil
        super.tearDown()
    }

    // MARK: - Storage and Retrieval Tests

    func testCacheAndRetrieveResponse() {
        cacheManager.cache(response: "It's sunny today", forQuery: "What's the weather?")

        // Allow async write to complete
        let expectation = expectation(description: "Cache write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let cached = cacheManager.getCachedResponse(for: "What's the weather?")

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.text, "It's sunny today")
        XCTAssertEqual(cached?.source, "claude_api")
        XCTAssertFalse(cached!.isExpired)
    }

    func testCacheNormalizesQueryCase() {
        cacheManager.cache(response: "Result", forQuery: "HELLO WORLD")

        let expectation = expectation(description: "Cache write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let cached = cacheManager.getCachedResponse(for: "hello world")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.text, "Result")
    }

    func testReturnsNilForMissingQuery() {
        let cached = cacheManager.getCachedResponse(for: "nonexistent query")
        XCTAssertNil(cached)
    }

    func testCustomSourceIsStored() {
        cacheManager.cache(response: "Fallback", forQuery: "test", source: "offline_fallback")

        let expectation = expectation(description: "Cache write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let cached = cacheManager.getCachedResponse(for: "test")
        XCTAssertEqual(cached?.source, "offline_fallback")
    }

    // MARK: - Cache Size and Count Tests

    func testEntryCounting() {
        cacheManager.cache(response: "Response 1", forQuery: "Query 1")
        cacheManager.cache(response: "Response 2", forQuery: "Query 2")
        cacheManager.cache(response: "Response 3", forQuery: "Query 3")

        let expectation = expectation(description: "Cache writes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)

        XCTAssertEqual(cacheManager.entryCount(), 3)
    }

    func testCacheSizeIsPositiveWithEntries() {
        cacheManager.cache(response: "Some cached response text", forQuery: "a query")

        let expectation = expectation(description: "Cache write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertGreaterThan(cacheManager.cacheSize(), 0)
    }

    // MARK: - Clear Cache Tests

    func testClearCacheRemovesAllEntries() {
        cacheManager.cache(response: "R1", forQuery: "Q1")
        cacheManager.cache(response: "R2", forQuery: "Q2")

        let writeExpectation = expectation(description: "Cache writes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            writeExpectation.fulfill()
        }
        wait(for: [writeExpectation], timeout: 2.0)

        cacheManager.clearCache()

        let clearExpectation = expectation(description: "Cache clear")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            clearExpectation.fulfill()
        }
        wait(for: [clearExpectation], timeout: 2.0)

        XCTAssertEqual(cacheManager.entryCount(), 0)
        XCTAssertNil(cacheManager.getCachedResponse(for: "Q1"))
    }

    // MARK: - TTL and Expiration Tests

    func testExpiredEntriesAreNotReturned() {
        // Create a cache with a very short TTL
        let shortTTLCache = OfflineCacheManager(
            directoryName: testDirectoryName + "_short",
            ttl: 0.1 // 100ms TTL
        )

        shortTTLCache.cache(response: "Ephemeral", forQuery: "temp query")

        let writeExpectation = expectation(description: "Cache write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            writeExpectation.fulfill()
        }
        wait(for: [writeExpectation], timeout: 2.0)

        // Wait for TTL to expire
        let expiryExpectation = expectation(description: "TTL expiry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expiryExpectation.fulfill()
        }
        wait(for: [expiryExpectation], timeout: 2.0)

        let cached = shortTTLCache.getCachedResponse(for: "temp query")
        XCTAssertNil(cached, "Expired entries should not be returned")

        // Cleanup
        shortTTLCache.clearCache()
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = documentsURL.appendingPathComponent(testDirectoryName + "_short")
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Constants Tests

    func testMaxCacheSizeIs50MB() {
        XCTAssertEqual(OfflineCacheManager.maxCacheSizeBytes, 50 * 1024 * 1024)
    }

    func testDefaultTTLIs24Hours() {
        XCTAssertEqual(OfflineCacheManager.defaultTTL, 24 * 60 * 60)
    }

    // MARK: - Cache Overwrite Tests

    func testCacheOverwritesExistingEntry() {
        cacheManager.cache(response: "Old response", forQuery: "my query")

        let firstWrite = expectation(description: "First write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            firstWrite.fulfill()
        }
        wait(for: [firstWrite], timeout: 2.0)

        cacheManager.cache(response: "New response", forQuery: "my query")

        let secondWrite = expectation(description: "Second write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            secondWrite.fulfill()
        }
        wait(for: [secondWrite], timeout: 2.0)

        let cached = cacheManager.getCachedResponse(for: "my query")
        XCTAssertEqual(cached?.text, "New response")
        XCTAssertEqual(cacheManager.entryCount(), 1)
    }
}
