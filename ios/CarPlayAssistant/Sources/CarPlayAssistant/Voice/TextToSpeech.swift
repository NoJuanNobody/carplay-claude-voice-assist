import AVFoundation
import Foundation

// MARK: - VoiceConfig

/// Configuration for text-to-speech voice output.
public struct VoiceConfig: Sendable {
    /// The voice identifier name (e.g. "com.apple.voice.compact.en-US.Samantha").
    public let name: String?

    /// The BCP-47 language tag (e.g. "en-US").
    public let language: String

    /// Speaking rate. Range 0.0 (slowest) to 1.0 (fastest). Default is ``AVSpeechUtteranceDefaultSpeechRate``.
    public let rate: Float

    /// Pitch multiplier. Range 0.5 to 2.0. Default is 1.0.
    public let pitch: Float

    /// Volume. Range 0.0 to 1.0. Default is 1.0.
    public let volume: Float

    public init(
        name: String? = nil,
        language: String = "en-US",
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitch: Float = 1.0,
        volume: Float = 1.0
    ) {
        self.name = name
        self.language = language
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
    }

    /// A sensible default configuration for CarPlay.
    public static let `default` = VoiceConfig()
}

// MARK: - TTSDelegate

/// Delegate protocol for receiving text-to-speech events.
public protocol TTSDelegate: AnyObject {
    /// Called when the synthesizer begins speaking an utterance.
    func didStartSpeaking()

    /// Called when the synthesizer finishes speaking an utterance.
    func didFinishSpeaking()

    /// Called when speaking is paused.
    func didPauseSpeaking()

    /// Called when speaking is resumed.
    func didResumeSpeaking()
}

// MARK: - Default Delegate Implementations

public extension TTSDelegate {
    func didResumeSpeaking() {}
}

// MARK: - TextToSpeech

/// Manages text-to-speech output using AVSpeechSynthesizer.
///
/// Supports queuing multiple utterances and respects user-configured voice preferences.
open class TextToSpeech: NSObject {

    // MARK: - Properties

    public weak var delegate: TTSDelegate?

    private let synthesizer = AVSpeechSynthesizer()

    /// The current voice configuration applied to new utterances.
    public var voiceConfig: VoiceConfig

    /// Whether the synthesizer is currently speaking.
    public var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    /// Whether the synthesizer is currently paused.
    public var isPaused: Bool {
        synthesizer.isPaused
    }

    // MARK: - Initialization

    /// Creates a new TextToSpeech instance with the given voice configuration.
    /// - Parameter voiceConfig: The default voice configuration. Defaults to ``VoiceConfig/default``.
    public init(voiceConfig: VoiceConfig = .default) {
        self.voiceConfig = voiceConfig
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Speaks the given text using the provided (or default) voice configuration.
    ///
    /// If the synthesizer is already speaking, the utterance is queued and will be
    /// spoken after the current utterance finishes.
    ///
    /// - Parameters:
    ///   - text: The text to speak.
    ///   - voice: The voice configuration to use. Defaults to the instance's ``voiceConfig``.
    open func speak(_ text: String, voice: VoiceConfig? = nil) {
        let config = voice ?? voiceConfig

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = config.rate
        utterance.pitchMultiplier = config.pitch
        utterance.volume = config.volume

        if let name = config.name {
            utterance.voice = AVSpeechSynthesisVoice(identifier: name)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: config.language)
        }

        synthesizer.speak(utterance)
    }

    /// Stops all speech immediately and clears the utterance queue.
    /// - Parameter boundary: The boundary at which to stop. Defaults to `.immediate`.
    open func stopSpeaking(at boundary: AVSpeechBoundary = .immediate) {
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        synthesizer.stopSpeaking(at: boundary)
    }

    /// Pauses speech at the next word boundary.
    public func pauseSpeaking() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Resumes speech after a pause.
    public func resumeSpeaking() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TextToSpeech: AVSpeechSynthesizerDelegate {

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        delegate?.didStartSpeaking()
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        delegate?.didFinishSpeaking()
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        delegate?.didPauseSpeaking()
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        delegate?.didResumeSpeaking()
    }
}
