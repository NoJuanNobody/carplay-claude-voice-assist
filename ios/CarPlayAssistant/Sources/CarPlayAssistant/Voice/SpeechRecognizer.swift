import Foundation
import Speech
import AVFoundation

// MARK: - SpeechRecognizerDelegate

/// Delegate protocol for receiving speech recognition results.
public protocol SpeechRecognizerDelegate: AnyObject {
    /// Called when speech has been recognized.
    /// - Parameters:
    ///   - text: The recognized text.
    ///   - isFinal: Whether this is the final recognition result for the current utterance.
    func didRecognizeText(_ text: String, isFinal: Bool)

    /// Called when an error occurs during recognition.
    /// - Parameter error: The error that occurred.
    func didEncounterRecognitionError(_ error: Error)
}

// MARK: - SpeechRecognizer

/// On-device speech-to-text using SFSpeechRecognizer.
///
/// Prefers on-device recognition when available for privacy and lower latency.
/// Streams partial results so the UI can display live transcription.
open class SpeechRecognizer {

    // MARK: - Properties

    public weak var delegate: SpeechRecognizerDelegate?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Whether recognition is currently active.
    public private(set) var isRecognizing = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Authorization

    /// Requests speech recognition authorization from the user.
    /// - Parameter completion: Called with the resulting authorization status.
    public static func requestAuthorization(completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }

    /// The current authorization status for speech recognition.
    public static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Recognition

    /// Starts speech recognition for the given locale.
    ///
    /// Installs a tap on the audio engine's input node and feeds buffers to the
    /// speech recognition request. Partial results are delivered to the delegate as
    /// they become available.
    ///
    /// - Parameter locale: The locale for speech recognition. Defaults to the current locale.
    /// - Throws: An error if the recognizer cannot be created or audio cannot be captured.
    public func startRecognition(locale: Locale = .current) throws {
        guard !isRecognizing else { return }

        guard Self.authorizationStatus == .authorized else {
            throw SpeechRecognizerError.notAuthorized(Self.authorizationStatus)
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechRecognizerError.recognizerUnavailable
        }

        speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prefer on-device recognition for privacy and latency.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.delegate?.didRecognizeText(text, isFinal: result.isFinal)

                if result.isFinal {
                    self.cleanUpRecognition()
                }
            }

            if let error {
                self.delegate?.didEncounterRecognitionError(error)
                self.cleanUpRecognition()
            }
        }

        // Configure audio engine tap for recognition input.
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecognizing = true
    }

    /// Appends an externally-captured audio buffer to the recognition request.
    ///
    /// Use this when audio is captured by ``VoiceCaptureEngine`` instead of an
    /// internal audio engine tap.
    /// - Parameter buffer: The PCM audio buffer to append.
    open func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    /// Starts recognition using externally-provided audio buffers (no internal engine tap).
    ///
    /// Call ``appendAudioBuffer(_:)`` to feed audio data.
    /// - Parameter locale: The locale for speech recognition. Defaults to the current locale.
    /// - Throws: An error if the recognizer cannot be created.
    open func startStreamingRecognition(locale: Locale = .current) throws {
        guard !isRecognizing else { return }

        guard Self.authorizationStatus == .authorized else {
            throw SpeechRecognizerError.notAuthorized(Self.authorizationStatus)
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechRecognizerError.recognizerUnavailable
        }

        speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.delegate?.didRecognizeText(text, isFinal: result.isFinal)

                if result.isFinal {
                    self.cleanUpRecognition()
                }
            }

            if let error {
                self.delegate?.didEncounterRecognitionError(error)
                self.cleanUpRecognition()
            }
        }

        isRecognizing = true
    }

    /// Stops the current speech recognition session.
    open func stopRecognition() {
        guard isRecognizing else { return }

        recognitionRequest?.endAudio()

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        recognitionTask?.cancel()
        cleanUpRecognition()
    }

    // MARK: - Private

    private func cleanUpRecognition() {
        recognitionRequest = nil
        recognitionTask = nil
        isRecognizing = false
    }
}

// MARK: - SpeechRecognizerError

/// Errors that can occur during speech recognition.
public enum SpeechRecognizerError: Error, CustomStringConvertible {
    case notAuthorized(SFSpeechRecognizerAuthorizationStatus)
    case recognizerUnavailable

    public var description: String {
        switch self {
        case .notAuthorized(let status):
            return "Speech recognition not authorized. Status: \(status.rawValue)"
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable for the requested locale."
        }
    }
}
