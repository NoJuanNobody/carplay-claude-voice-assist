import Foundation

// MARK: - OfflineResponse

/// A response generated locally without network access.
public struct OfflineResponse: Sendable {
    /// The response text.
    public let text: String

    /// Confidence level from 0.0 to 1.0.
    public let confidence: Double

    /// The category of the query that was handled.
    public let category: OfflineResponseCategory
}

// MARK: - OfflineResponseCategory

/// Categories of queries that can be handled offline.
public enum OfflineResponseCategory: String, Sendable {
    case time
    case math
    case unitConversion
    case preferences
    case general
}

// MARK: - LocalResponseEngine

/// Generates basic responses without network connectivity.
///
/// Handles time queries, basic arithmetic, unit conversions, and stored
/// preference recall using on-device pattern matching.
public final class LocalResponseEngine {

    // MARK: - Pattern Definitions

    private static let timePatterns: [String] = [
        "what time", "current time", "what's the time", "tell me the time",
        "what is the time", "time is it", "what hour", "the date",
        "what day", "today's date", "what's today", "what is today"
    ]

    private static let mathOperatorPatterns: [(pattern: String, operation: (Double, Double) -> Double, name: String)] = [
        ("plus", (+), "addition"),
        ("\\+", (+), "addition"),
        ("added to", (+), "addition"),
        ("minus", (-), "subtraction"),
        ("\\-", (-), "subtraction"),
        ("subtract", (-), "subtraction"),
        ("times", (*), "multiplication"),
        ("\\*", (*), "multiplication"),
        ("multiplied by", (*), "multiplication"),
        ("divided by", (/), "division"),
        ("\\/", (/), "division"),
        ("over", (/), "division")
    ]

    private static let conversionPatterns: [(regex: String, convert: (Double) -> Double, fromUnit: String, toUnit: String)] = [
        // Temperature
        ("(\\d+\\.?\\d*)\\s*(fahrenheit|f)\\s*(to|in)\\s*(celsius|c)", { ($0 - 32) * 5.0 / 9.0 }, "F", "C"),
        ("(\\d+\\.?\\d*)\\s*(celsius|c)\\s*(to|in)\\s*(fahrenheit|f)", { $0 * 9.0 / 5.0 + 32 }, "C", "F"),
        // Distance
        ("(\\d+\\.?\\d*)\\s*(miles?|mi)\\s*(to|in)\\s*(kilometers?|km)", { $0 * 1.60934 }, "mi", "km"),
        ("(\\d+\\.?\\d*)\\s*(kilometers?|km)\\s*(to|in)\\s*(miles?|mi)", { $0 / 1.60934 }, "km", "mi"),
        // Weight
        ("(\\d+\\.?\\d*)\\s*(pounds?|lbs?)\\s*(to|in)\\s*(kilograms?|kg)", { $0 * 0.453592 }, "lb", "kg"),
        ("(\\d+\\.?\\d*)\\s*(kilograms?|kg)\\s*(to|in)\\s*(pounds?|lbs?)", { $0 / 0.453592 }, "kg", "lb"),
        // Volume
        ("(\\d+\\.?\\d*)\\s*(gallons?|gal)\\s*(to|in)\\s*(liters?|l)", { $0 * 3.78541 }, "gal", "L"),
        ("(\\d+\\.?\\d*)\\s*(liters?|l)\\s*(to|in)\\s*(gallons?|gal)", { $0 / 3.78541 }, "L", "gal"),
        // Speed
        ("(\\d+\\.?\\d*)\\s*(mph)\\s*(to|in)\\s*(km/?h|kph)", { $0 * 1.60934 }, "mph", "km/h"),
        ("(\\d+\\.?\\d*)\\s*(km/?h|kph)\\s*(to|in)\\s*(mph)", { $0 / 1.60934 }, "km/h", "mph")
    ]

    // MARK: - Properties

    private var storedPreferences: [String: String] = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Attempts to process a query offline.
    /// - Parameter text: The user's query text.
    /// - Returns: An offline response if the query can be handled, or nil.
    public func processOffline(_ text: String) -> OfflineResponse? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let timeResponse = handleTimeQuery(normalized) {
            return timeResponse
        }

        if let mathResponse = handleMathQuery(normalized) {
            return mathResponse
        }

        if let conversionResponse = handleUnitConversion(normalized) {
            return conversionResponse
        }

        if let prefResponse = handlePreferenceQuery(normalized) {
            return prefResponse
        }

        return nil
    }

    /// Stores a user preference for offline recall.
    /// - Parameters:
    ///   - key: The preference key (e.g., "home_address", "favorite_station").
    ///   - value: The preference value.
    public func storePreference(key: String, value: String) {
        storedPreferences[key.lowercased()] = value
    }

    /// Retrieves a stored preference.
    /// - Parameter key: The preference key.
    /// - Returns: The stored value, or nil if not found.
    public func getPreference(key: String) -> String? {
        storedPreferences[key.lowercased()]
    }

    /// Loads preferences from a dictionary (e.g., synced from server).
    /// - Parameter preferences: A dictionary of preference key-value pairs.
    public func loadPreferences(_ preferences: [String: String]) {
        for (key, value) in preferences {
            storedPreferences[key.lowercased()] = value
        }
    }

    // MARK: - Time Handling

    private func handleTimeQuery(_ text: String) -> OfflineResponse? {
        let isTimeQuery = Self.timePatterns.contains { text.contains($0) }
        guard isTimeQuery else { return nil }

        let now = Date()
        let formatter = DateFormatter()

        if text.contains("date") || text.contains("day") || text.contains("today") {
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            let dateString = formatter.string(from: now)
            return OfflineResponse(
                text: "It's \(dateString).",
                confidence: 0.95,
                category: .time
            )
        }

        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeString = formatter.string(from: now)
        return OfflineResponse(
            text: "The current time is \(timeString).",
            confidence: 0.95,
            category: .time
        )
    }

    // MARK: - Math Handling

    private func handleMathQuery(_ text: String) -> OfflineResponse? {
        // Try to find a pattern like "what is X operator Y" or "X operator Y"
        let cleaned = text
            .replacingOccurrences(of: "what is", with: "")
            .replacingOccurrences(of: "what's", with: "")
            .replacingOccurrences(of: "calculate", with: "")
            .replacingOccurrences(of: "compute", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for op in Self.mathOperatorPatterns {
            let pattern = "(\\-?\\d+\\.?\\d*)\\s*\(op.pattern)\\s*(\\-?\\d+\\.?\\d*)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            guard let match = regex.firstMatch(in: cleaned, options: [], range: range) else { continue }

            guard let firstRange = Range(match.range(at: 1), in: cleaned),
                  let lastRange = Range(match.range(at: match.numberOfRanges - 1), in: cleaned),
                  let first = Double(cleaned[firstRange]),
                  let second = Double(cleaned[lastRange]) else { continue }

            // Guard against division by zero
            if op.name == "division" && second == 0 {
                return OfflineResponse(
                    text: "I can't divide by zero.",
                    confidence: 0.99,
                    category: .math
                )
            }

            let result = op.operation(first, second)
            let formattedResult = formatNumber(result)

            return OfflineResponse(
                text: "\(formatNumber(first)) \(operatorSymbol(op.name)) \(formatNumber(second)) equals \(formattedResult).",
                confidence: 0.99,
                category: .math
            )
        }

        return nil
    }

    // MARK: - Unit Conversion Handling

    private func handleUnitConversion(_ text: String) -> OfflineResponse? {
        let cleaned = text
            .replacingOccurrences(of: "convert", with: "")
            .replacingOccurrences(of: "what is", with: "")
            .replacingOccurrences(of: "what's", with: "")
            .replacingOccurrences(of: "how many", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for conversion in Self.conversionPatterns {
            guard let regex = try? NSRegularExpression(pattern: conversion.regex, options: .caseInsensitive) else { continue }
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            guard let match = regex.firstMatch(in: cleaned, options: [], range: range) else { continue }

            guard let valueRange = Range(match.range(at: 1), in: cleaned),
                  let value = Double(cleaned[valueRange]) else { continue }

            let converted = conversion.convert(value)

            return OfflineResponse(
                text: "\(formatNumber(value)) \(conversion.fromUnit) is approximately \(formatNumber(converted)) \(conversion.toUnit).",
                confidence: 0.9,
                category: .unitConversion
            )
        }

        return nil
    }

    // MARK: - Preference Handling

    private func handlePreferenceQuery(_ text: String) -> OfflineResponse? {
        let preferenceKeywords: [(keywords: [String], key: String, label: String)] = [
            (["home address", "my home", "where do i live", "my address"], "home_address", "home address"),
            (["work address", "my work", "my office", "where do i work"], "work_address", "work address"),
            (["favorite station", "my station", "preferred station"], "favorite_station", "favorite station"),
            (["favorite music", "my music", "preferred music", "music preference"], "favorite_music", "music preference"),
            (["my name", "what's my name", "what is my name", "who am i"], "user_name", "name")
        ]

        for pref in preferenceKeywords {
            let matches = pref.keywords.contains { text.contains($0) }
            guard matches else { continue }

            if let value = storedPreferences[pref.key] {
                return OfflineResponse(
                    text: "Your \(pref.label) is \(value).",
                    confidence: 0.85,
                    category: .preferences
                )
            } else {
                return OfflineResponse(
                    text: "I don't have your \(pref.label) saved. You can set it when you're back online.",
                    confidence: 0.7,
                    category: .preferences
                )
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private func operatorSymbol(_ name: String) -> String {
        switch name {
        case "addition": return "+"
        case "subtraction": return "-"
        case "multiplication": return "x"
        case "division": return "/"
        default: return name
        }
    }
}
