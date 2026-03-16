import Foundation

// MARK: - ComplianceResult

/// The result of a UI compliance check on a response.
public struct ComplianceResult: Sendable {
    /// The original unmodified text.
    public let originalText: String

    /// Text suitable for display on the CarPlay screen (may be truncated).
    public let displayText: String

    /// Text suitable for spoken output via TTS (may differ from display).
    public let spokenText: String

    /// Whether the text was modified to comply with driving rules.
    public let wasModified: Bool

    /// List of compliance rules that were applied.
    public let appliedRules: [ComplianceRule]
}

// MARK: - ComplianceRule

/// Describes a compliance rule that was triggered.
public enum ComplianceRule: String, Sendable {
    case displayTruncated
    case voiceTruncated
    case listItemsLimited
    case phoneNumberRedacted
    case urlRedacted
}

// MARK: - UIComplianceEngine

/// Enforces Apple CarPlay Human Interface Guidelines and driving safety rules.
///
/// Limits list items, truncates responses for display and voice, and redacts
/// distracting content based on the current driving state.
public final class UIComplianceEngine {

    // MARK: - Configuration

    /// Maximum characters to display on CarPlay screen while driving.
    public var maxDisplayCharacters: [DrivingState: Int] = [
        .parked: 500,
        .city: 160,
        .highway: 80,
        .unknown: 160
    ]

    /// Maximum characters for spoken output.
    public var maxSpokenCharacters: [DrivingState: Int] = [
        .parked: 2000,
        .city: 400,
        .highway: 200,
        .unknown: 400
    ]

    /// Maximum list items allowed per Apple CarPlay HIG while driving.
    public var maxListItemsDriving: Int = 12

    /// Maximum list items while parked.
    public var maxListItemsParked: Int = 24

    private static let phonePattern = try! NSRegularExpression(
        pattern: #"\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#,
        options: []
    )

    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://\S+|www\.\S+"#,
        options: [.caseInsensitive]
    )

    private static let truncationSuffix = " ...I'll share more when you're parked."

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Validates and adjusts a response for CarPlay compliance.
    ///
    /// - Parameters:
    ///   - text: The response text to validate.
    ///   - drivingState: The current driving state.
    /// - Returns: A `ComplianceResult` with adjusted display and spoken text.
    public func validateResponse(
        _ text: String,
        drivingState: DrivingState
    ) -> ComplianceResult {
        var displayText = text
        var spokenText = text
        var rules: [ComplianceRule] = []

        // Redact phone numbers while driving
        if drivingState != .parked {
            let redactedPhone = Self.redactPhoneNumbers(in: displayText)
            if redactedPhone != displayText {
                rules.append(.phoneNumberRedacted)
                displayText = redactedPhone
                spokenText = Self.redactPhoneNumbers(in: spokenText)
            }

            let redactedURL = Self.redactURLs(in: displayText)
            if redactedURL != displayText {
                rules.append(.urlRedacted)
                displayText = redactedURL
                spokenText = Self.redactURLs(in: spokenText)
            }
        }

        // Truncate display text
        let maxDisplay = maxDisplayCharacters[drivingState] ?? 160
        if displayText.count > maxDisplay {
            let endIndex = displayText.index(
                displayText.startIndex,
                offsetBy: max(0, maxDisplay - Self.truncationSuffix.count)
            )
            displayText = String(displayText[..<endIndex]) + Self.truncationSuffix
            rules.append(.displayTruncated)
        }

        // Truncate spoken text
        let maxSpoken = maxSpokenCharacters[drivingState] ?? 400
        if spokenText.count > maxSpoken {
            // Truncate at last sentence boundary before the limit
            let truncated = Self.truncateAtSentenceBoundary(
                spokenText,
                maxLength: maxSpoken
            )
            if truncated.count < spokenText.count {
                spokenText = truncated + Self.truncationSuffix
                rules.append(.voiceTruncated)
            }
        }

        return ComplianceResult(
            originalText: text,
            displayText: displayText,
            spokenText: spokenText,
            wasModified: !rules.isEmpty,
            appliedRules: rules
        )
    }

    /// Returns the maximum number of list items for the given driving state.
    public func maxListItems(for drivingState: DrivingState) -> Int {
        switch drivingState {
        case .parked:
            return maxListItemsParked
        case .city, .highway, .unknown:
            return maxListItemsDriving
        }
    }

    /// Limits an array to the compliant number of items.
    public func limitListItems<T>(
        _ items: [T],
        drivingState: DrivingState
    ) -> (items: [T], wasLimited: Bool) {
        let max = maxListItems(for: drivingState)
        if items.count > max {
            return (Array(items.prefix(max)), true)
        }
        return (items, false)
    }

    // MARK: - Private Helpers

    private static func redactPhoneNumbers(in text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return phonePattern.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "[phone hidden]"
        )
    }

    private static func redactURLs(in text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return urlPattern.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "[link hidden]"
        )
    }

    private static func truncateAtSentenceBoundary(
        _ text: String,
        maxLength: Int
    ) -> String {
        guard text.count > maxLength else { return text }

        let endIndex = text.index(text.startIndex, offsetBy: maxLength)
        let substring = String(text[..<endIndex])

        // Find the last sentence-ending punctuation
        if let lastPeriod = substring.lastIndex(where: { ".!?".contains($0) }) {
            let nextIndex = text.index(after: lastPeriod)
            return String(text[..<nextIndex])
        }

        // No sentence boundary found; truncate at word boundary
        if let lastSpace = substring.lastIndex(of: " ") {
            return String(text[..<lastSpace])
        }

        return substring
    }
}
