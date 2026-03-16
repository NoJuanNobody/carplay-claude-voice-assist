import Combine
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - EmergencyType

/// Types of emergencies the system can detect and handle.
public enum EmergencyType: String, Sendable, CaseIterable {
    case crash
    case medical
    case roadside
    case sos
}

// MARK: - EmergencyAction

/// Actions the system can take in response to an emergency.
public enum EmergencyAction: String, Sendable {
    case call911
    case callRoadside
    case alertEmergencyContact
}

// MARK: - EmergencyEvent

/// Represents a detected emergency event with context.
public struct EmergencyEvent: Sendable {
    public let type: EmergencyType
    public let action: EmergencyAction
    public let location: CLLocation?
    public let timestamp: Date
    public let confidence: Double

    public init(
        type: EmergencyType,
        action: EmergencyAction,
        location: CLLocation?,
        timestamp: Date = Date(),
        confidence: Double = 1.0
    ) {
        self.type = type
        self.action = action
        self.location = location
        self.timestamp = timestamp
        self.confidence = confidence
    }
}

// MARK: - EmergencyProtocolDelegate

/// Delegate for receiving emergency protocol notifications.
public protocol EmergencyProtocolDelegate: AnyObject {
    /// Called when an emergency is detected, before action is taken.
    func emergencyProtocol(
        _ protocol: EmergencyProtocol,
        didDetectEmergency event: EmergencyEvent
    )

    /// Called after an emergency action has been initiated.
    func emergencyProtocol(
        _ protocol: EmergencyProtocol,
        didInitiateAction action: EmergencyAction,
        for event: EmergencyEvent
    )

    /// Called if the emergency action failed.
    func emergencyProtocol(
        _ protocol: EmergencyProtocol,
        didFailAction action: EmergencyAction,
        error: Error
    )
}

// MARK: - EmergencyProtocol

/// Handles emergency detection and response on the device.
///
/// Integrates crash detection (when available), emergency keyword detection,
/// and automated emergency calling via the `tel:` URL scheme. Shares the
/// user's location automatically when an emergency is triggered.
public final class EmergencyProtocol: ObservableObject {

    // MARK: - Published Properties

    /// Whether an emergency is currently active.
    @Published public private(set) var isEmergencyActive: Bool = false

    /// The most recent emergency event, if any.
    @Published public private(set) var activeEmergency: EmergencyEvent?

    // MARK: - Properties

    public weak var delegate: EmergencyProtocolDelegate?

    /// The phone number for roadside assistance. Configurable per user.
    public var roadsideAssistanceNumber: String = "1-800-222-4357"

    /// The user's emergency contact phone number, if configured.
    public var emergencyContactNumber: String?

    /// Number of seconds to wait before auto-dialing after crash detection.
    /// Gives the user a chance to cancel if it was a false positive.
    public var crashAutoDialDelay: TimeInterval = 10.0

    private let locationProvider: DrivingStateMonitor?
    private var crashAutoDialTimer: Timer?
    private var emergencyHistory: [EmergencyEvent] = []

    // MARK: - Emergency Keywords

    private static let emergencyKeywords: [EmergencyType: [String]] = [
        .crash: ["crash", "crashed", "accident", "collision", "hit", "wreck"],
        .medical: [
            "heart attack", "stroke", "seizure", "choking", "unconscious",
            "bleeding", "can't breathe", "not breathing", "chest pain"
        ],
        .roadside: [
            "flat tire", "broke down", "tow truck", "overheating",
            "stalled", "won't start", "dead battery", "locked out"
        ],
        .sos: ["help me", "emergency", "sos", "danger"]
    ]

    // MARK: - Initialization

    /// Creates an emergency protocol handler.
    /// - Parameter locationProvider: An optional driving state monitor for location data.
    public init(locationProvider: DrivingStateMonitor? = nil) {
        self.locationProvider = locationProvider
    }

    // MARK: - Public API

    /// Triggers an emergency of the given type. Initiates the appropriate action.
    ///
    /// - Parameter type: The type of emergency to trigger.
    public func triggerEmergency(type: EmergencyType) {
        let action = actionForType(type)
        let location = locationProvider?.currentLocation

        let event = EmergencyEvent(
            type: type,
            action: action,
            location: location
        )

        activeEmergency = event
        isEmergencyActive = true
        emergencyHistory.append(event)

        delegate?.emergencyProtocol(self, didDetectEmergency: event)

        if type == .crash {
            // Delay auto-dial for crash to allow cancellation of false positives
            startCrashAutoDialCountdown(event: event)
        } else {
            executeAction(event: event)
        }
    }

    /// Checks text input for emergency keywords and triggers if found.
    ///
    /// - Parameter text: The user's spoken or typed input.
    /// - Returns: The detected emergency type, or nil if none found.
    @discardableResult
    public func checkForEmergency(in text: String) -> EmergencyType? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for (type, keywords) in Self.emergencyKeywords {
            if keywords.contains(where: { normalized.contains($0) }) {
                triggerEmergency(type: type)
                return type
            }
        }

        return nil
    }

    /// Cancels the current emergency, stopping any pending auto-dial.
    public func cancelEmergency() {
        crashAutoDialTimer?.invalidate()
        crashAutoDialTimer = nil
        isEmergencyActive = false
        activeEmergency = nil
    }

    /// Returns the emergency history for reporting to the backend.
    public func getEmergencyHistory() -> [EmergencyEvent] {
        emergencyHistory
    }

    /// Shares the current location as a formatted string for emergency services.
    public func formattedLocationForEmergency() -> String? {
        guard let location = locationProvider?.currentLocation else {
            return nil
        }
        let lat = String(format: "%.6f", location.coordinate.latitude)
        let lon = String(format: "%.6f", location.coordinate.longitude)
        return "Lat: \(lat), Lon: \(lon)"
    }

    // MARK: - Private Methods

    private func actionForType(_ type: EmergencyType) -> EmergencyAction {
        switch type {
        case .crash:
            return .call911
        case .medical:
            return .call911
        case .roadside:
            return .callRoadside
        case .sos:
            return .call911
        }
    }

    private func startCrashAutoDialCountdown(event: EmergencyEvent) {
        crashAutoDialTimer?.invalidate()
        crashAutoDialTimer = Timer.scheduledTimer(
            withTimeInterval: crashAutoDialDelay,
            repeats: false
        ) { [weak self] _ in
            self?.executeAction(event: event)
        }
    }

    private func executeAction(event: EmergencyEvent) {
        let phoneNumber: String

        switch event.action {
        case .call911:
            phoneNumber = "911"
        case .callRoadside:
            phoneNumber = roadsideAssistanceNumber
        case .alertEmergencyContact:
            phoneNumber = emergencyContactNumber ?? "911"
        }

        placeCall(to: phoneNumber, for: event)
    }

    private func placeCall(to number: String, for event: EmergencyEvent) {
        let sanitized = number.replacingOccurrences(
            of: "[^0-9+]",
            with: "",
            options: .regularExpression
        )

        guard let url = URL(string: "tel://\(sanitized)") else {
            let error = NSError(
                domain: "EmergencyProtocol",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid phone number: \(number)"]
            )
            delegate?.emergencyProtocol(self, didFailAction: event.action, error: error)
            return
        }

        #if canImport(UIKit) && !os(watchOS)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:]) { success in
                    if success {
                        self.delegate?.emergencyProtocol(
                            self,
                            didInitiateAction: event.action,
                            for: event
                        )
                    } else {
                        let error = NSError(
                            domain: "EmergencyProtocol",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Failed to open tel URL"
                            ]
                        )
                        self.delegate?.emergencyProtocol(
                            self,
                            didFailAction: event.action,
                            error: error
                        )
                    }
                }
            }
        }
        #else
        // Non-UIKit platforms: notify delegate only
        delegate?.emergencyProtocol(self, didInitiateAction: event.action, for: event)
        #endif
    }
}
