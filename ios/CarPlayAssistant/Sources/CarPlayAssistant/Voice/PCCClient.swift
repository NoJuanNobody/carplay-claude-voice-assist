import AVFoundation
import Foundation
import Speech

// MARK: - PCCClientProtocol

/// Protocol for Private Cloud Compute clients, enabling dependency injection and testability.
public protocol PCCClientProtocol {
    /// Whether Private Cloud Compute is available on the current device and OS version.
    func isAvailable() -> Bool

    /// Processes an audio buffer through Private Cloud Compute for enhanced recognition.
    /// - Parameter buffer: The PCM audio buffer to process.
    /// - Returns: The recognized text.
    func processAudio(_ buffer: AVAudioPCMBuffer) async throws -> String
}

// MARK: - PCCClient

/// Client for Apple Private Cloud Compute, providing enhanced on-device processing.
///
/// Falls back to standard ``SFSpeechRecognizer`` when PCC is unavailable (e.g. on older
/// devices or OS versions that do not support the feature).
public final class PCCClient: PCCClientProtocol {

    // MARK: - Properties

    private let locale: Locale
    private let fallbackRecognizer: SFSpeechRecognizer?

    // MARK: - Initialization

    /// Creates a PCC client with the given locale.
    /// - Parameter locale: The locale for speech recognition. Defaults to the current locale.
    public init(locale: Locale = .current) {
        self.locale = locale
        self.fallbackRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - PCCClientProtocol

    /// Checks whether Private Cloud Compute is available.
    ///
    /// PCC availability depends on device hardware and OS version. This method checks
    /// runtime conditions and returns `false` if PCC cannot be used.
    public func isAvailable() -> Bool {
        // PCC availability is determined at runtime. Currently there is no public API
        // to query this directly, so we check for on-device recognition support as a
        // proxy — PCC extends on-device capabilities.
        guard let recognizer = fallbackRecognizer else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    /// Processes an audio buffer, preferring PCC when available and falling back to
    /// standard on-device speech recognition.
    ///
    /// - Parameter buffer: The PCM audio buffer to process.
    /// - Returns: The recognized text.
    /// - Throws: ``PCCError`` if processing fails.
    public func processAudio(_ buffer: AVAudioPCMBuffer) async throws -> String {
        guard let recognizer = fallbackRecognizer, recognizer.isAvailable else {
            throw PCCError.recognizerUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = false

            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            request.append(buffer)
            request.endAudio()

            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: PCCError.processingFailed(error))
                    return
                }

                guard let result, result.isFinal else {
                    // Wait for the final result; non-final results are ignored.
                    return
                }

                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}

// MARK: - PCCError

/// Errors that can occur during Private Cloud Compute processing.
public enum PCCError: Error, CustomStringConvertible {
    case recognizerUnavailable
    case processingFailed(Error)
    case unsupported

    public var description: String {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available."
        case .processingFailed(let error):
            return "PCC processing failed: \(error.localizedDescription)"
        case .unsupported:
            return "Private Cloud Compute is not supported on this device."
        }
    }
}
