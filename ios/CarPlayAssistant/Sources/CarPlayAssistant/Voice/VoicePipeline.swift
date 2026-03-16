import AVFoundation
import Combine
import Foundation

// MARK: - VoicePipelineState

/// Represents the current state of the voice pipeline.
public enum VoicePipelineState: String, Sendable {
    case idle
    case listening
    case processing
    case speaking
}

// MARK: - VoicePipelineError

/// Errors that can occur in the voice pipeline.
public enum VoicePipelineError: Error, CustomStringConvertible {
    case captureError(Error)
    case recognitionError(Error)
    case processingError(Error)
    case speechError(Error)
    case invalidStateTransition(from: VoicePipelineState, to: VoicePipelineState)

    public var description: String {
        switch self {
        case .captureError(let error):
            return "Audio capture error: \(error.localizedDescription)"
        case .recognitionError(let error):
            return "Speech recognition error: \(error.localizedDescription)"
        case .processingError(let error):
            return "Processing error: \(error.localizedDescription)"
        case .speechError(let error):
            return "Text-to-speech error: \(error.localizedDescription)"
        case .invalidStateTransition(let from, let to):
            return "Invalid state transition from \(from.rawValue) to \(to.rawValue)."
        }
    }
}

// MARK: - VoicePipelineDelegate

/// Delegate protocol for receiving voice pipeline state changes.
public protocol VoicePipelineDelegate: AnyObject {
    /// Called when the pipeline state changes.
    func voicePipelineDidChangeState(_ state: VoicePipelineState)

    /// Called when partial speech recognition text is available.
    func voicePipelineDidReceivePartialText(_ text: String)

    /// Called when the pipeline encounters an error.
    func voicePipelineDidEncounterError(_ error: VoicePipelineError)
}

// MARK: - VoicePipeline

/// Orchestrates the full voice interaction pipeline: capture, recognize, process, and speak.
///
/// Manages state transitions between idle, listening, processing, and speaking,
/// and coordinates the ``VoiceCaptureEngine``, ``SpeechRecognizer``, and ``TextToSpeech``
/// components.
public final class VoicePipeline: NSObject {

    // MARK: - Properties

    public weak var delegate: VoicePipelineDelegate?

    /// The current pipeline state.
    public private(set) var state: VoicePipelineState = .idle {
        didSet {
            guard state != oldValue else { return }
            delegate?.voicePipelineDidChangeState(state)
        }
    }

    /// Publishes pipeline state changes via Combine.
    public let statePublisher = CurrentValueSubject<VoicePipelineState, Never>(.idle)

    private let captureEngine: VoiceCaptureEngine
    private let speechRecognizer: SpeechRecognizer
    private let textToSpeech: TextToSpeech
    private let pccClient: PCCClientProtocol

    private var recognizedText: String = ""
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Creates a voice pipeline with the given components.
    /// - Parameters:
    ///   - captureEngine: The audio capture engine. Defaults to a new instance.
    ///   - speechRecognizer: The speech recognizer. Defaults to a new instance.
    ///   - textToSpeech: The TTS engine. Defaults to a new instance.
    ///   - pccClient: The Private Cloud Compute client. Defaults to a new instance.
    public init(
        captureEngine: VoiceCaptureEngine = VoiceCaptureEngine(),
        speechRecognizer: SpeechRecognizer = SpeechRecognizer(),
        textToSpeech: TextToSpeech = TextToSpeech(),
        pccClient: PCCClientProtocol = PCCClient()
    ) {
        self.captureEngine = captureEngine
        self.speechRecognizer = speechRecognizer
        self.textToSpeech = textToSpeech
        self.pccClient = pccClient
        super.init()

        self.captureEngine.delegate = self
        self.speechRecognizer.delegate = self
        self.textToSpeech.delegate = self
    }

    // MARK: - Public API

    /// Activates the voice pipeline, transitioning from idle to listening.
    ///
    /// Starts audio capture and speech recognition.
    public func activate() {
        guard state == .idle else {
            delegate?.voicePipelineDidEncounterError(
                .invalidStateTransition(from: state, to: .listening)
            )
            return
        }

        do {
            try captureEngine.startCapture()
            try speechRecognizer.startStreamingRecognition()
            transition(to: .listening)
        } catch {
            delegate?.voicePipelineDidEncounterError(.captureError(error))
            reset()
        }
    }

    /// Deactivates the voice pipeline, stopping all components and returning to idle.
    public func deactivate() {
        captureEngine.stopCapture()
        speechRecognizer.stopRecognition()
        textToSpeech.stopSpeaking()
        transition(to: .idle)
        recognizedText = ""
    }

    /// Processes the currently recognized user input and returns the text.
    ///
    /// Stops listening, transitions to processing, and returns the final recognized
    /// text. The caller is responsible for sending this text to the backend and calling
    /// ``speak(_:)`` with the response.
    ///
    /// - Returns: The recognized user input text.
    public func processUserInput() async -> String {
        guard state == .listening else { return "" }

        captureEngine.stopCapture()
        speechRecognizer.stopRecognition()
        transition(to: .processing)

        // Allow a small delay for any final recognition results.
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let result = recognizedText
        recognizedText = ""
        return result
    }

    /// Speaks the given text through the TTS engine.
    ///
    /// Transitions the pipeline to the speaking state and back to idle when finished.
    /// - Parameter text: The text to speak.
    public func speak(_ text: String) {
        transition(to: .speaking)
        textToSpeech.speak(text)
    }

    // MARK: - Private

    private func transition(to newState: VoicePipelineState) {
        state = newState
        statePublisher.send(newState)
    }

    private func reset() {
        captureEngine.stopCapture()
        speechRecognizer.stopRecognition()
        textToSpeech.stopSpeaking()
        recognizedText = ""
        transition(to: .idle)
    }
}

// MARK: - VoiceCaptureDelegate

extension VoicePipeline: VoiceCaptureDelegate {
    public func didCaptureAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        speechRecognizer.appendAudioBuffer(buffer)
    }
}

// MARK: - SpeechRecognizerDelegate

extension VoicePipeline: SpeechRecognizerDelegate {
    public func didRecognizeText(_ text: String, isFinal: Bool) {
        recognizedText = text
        delegate?.voicePipelineDidReceivePartialText(text)
    }

    public func didEncounterRecognitionError(_ error: Error) {
        delegate?.voicePipelineDidEncounterError(.recognitionError(error))
    }
}

// MARK: - TTSDelegate

extension VoicePipeline: TTSDelegate {
    public func didStartSpeaking() {
        // State is already .speaking from speak(_:) call.
    }

    public func didFinishSpeaking() {
        transition(to: .idle)
    }

    public func didPauseSpeaking() {
        // Remain in speaking state while paused.
    }

    public func didResumeSpeaking() {
        // Remain in speaking state.
    }
}
