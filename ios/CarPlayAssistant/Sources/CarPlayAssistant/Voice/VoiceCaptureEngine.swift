import AVFoundation
import Foundation

// MARK: - VoiceCaptureDelegate

/// Delegate protocol for receiving captured audio buffers from the voice capture engine.
public protocol VoiceCaptureDelegate: AnyObject {
    /// Called when a new audio buffer has been captured.
    /// - Parameter buffer: The captured PCM audio buffer at 16kHz mono 16-bit.
    func didCaptureAudioBuffer(_ buffer: AVAudioPCMBuffer)
}

// MARK: - VoiceCaptureEngine

/// Captures audio input using AVAudioEngine, configured for CarPlay voice interactions.
///
/// Audio is captured at 16 kHz, mono, 16-bit — the format expected by speech recognition
/// and the backend streaming API.
open class VoiceCaptureEngine {

    // MARK: - Properties

    public weak var delegate: VoiceCaptureDelegate?

    /// The target sample rate for captured audio.
    public static let sampleRate: Double = 16_000

    /// The target channel count for captured audio.
    public static let channelCount: AVAudioChannelCount = 1

    /// The target bit depth for captured audio.
    public static let bitDepth: UInt32 = 16

    private let audioEngine = AVAudioEngine()
    private var isCapturing = false
    private var isPaused = false

    /// The recording format used for the input tap.
    private var captureFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: Self.channelCount,
            interleaved: true
        )
    }

    // MARK: - Initialization

    public init() {
        #if os(iOS)
        registerForInterruptionNotifications()
        #endif
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopCapture()
    }

    // MARK: - Public API

    /// Starts capturing audio from the device microphone.
    ///
    /// Configures the audio session for CarPlay voice chat and installs a tap on the
    /// audio engine's input node.
    /// - Throws: An error if the audio session or engine cannot be configured.
    open func startCapture() throws {
        guard !isCapturing else { return }

        #if os(iOS)
        try configureAudioSession()
        #endif

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = captureFormat else {
            throw VoiceCaptureError.formatUnavailable
        }

        // If hardware format differs from target, use a converter.
        if hardwareFormat.sampleRate != Self.sampleRate ||
            hardwareFormat.channelCount != Self.channelCount {
            installConvertingTap(on: inputNode, from: hardwareFormat, to: targetFormat)
        } else {
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: targetFormat) { [weak self] buffer, _ in
                guard let self, !self.isPaused else { return }
                self.delegate?.didCaptureAudioBuffer(buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isCapturing = true
        isPaused = false
    }

    /// Stops audio capture and tears down the audio engine tap.
    open func stopCapture() {
        guard isCapturing else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false
        isPaused = false
    }

    /// Pauses audio capture without tearing down the engine.
    ///
    /// Buffers captured while paused are silently discarded.
    public func pauseCapture() {
        guard isCapturing else { return }
        isPaused = true
        audioEngine.pause()
    }

    /// Resumes audio capture after a pause.
    /// - Throws: An error if the audio engine fails to restart.
    public func resumeCapture() throws {
        guard isCapturing, isPaused else { return }
        try audioEngine.start()
        isPaused = false
    }

    // MARK: - Audio Session

    #if os(iOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(Self.sampleRate)
        try session.setPreferredIOBufferDuration(0.02) // 20 ms
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    #endif

    // MARK: - Format Conversion

    private func installConvertingTap(
        on inputNode: AVAudioInputNode,
        from sourceFormat: AVAudioFormat,
        to targetFormat: AVAudioFormat
    ) {
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { [weak self] buffer, _ in
            guard let self, !self.isPaused else { return }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * (Self.sampleRate / sourceFormat.sampleRate)
            )
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                return
            }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData, error == nil {
                self.delegate?.didCaptureAudioBuffer(convertedBuffer)
            }
        }
    }

    // MARK: - Interruption Handling

    #if os(iOS)
    private func registerForInterruptionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }

        switch type {
        case .began:
            pauseCapture()
        case .ended:
            let optionsRaw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) {
                try? resumeCapture()
            }
        @unknown default:
            break
        }
    }
    #endif
}

// MARK: - VoiceCaptureError

/// Errors that can occur during voice capture.
public enum VoiceCaptureError: Error, CustomStringConvertible {
    case formatUnavailable
    case engineStartFailed(Error)

    public var description: String {
        switch self {
        case .formatUnavailable:
            return "The required audio format (16kHz mono Int16) is not available."
        case .engineStartFailed(let error):
            return "Audio engine failed to start: \(error.localizedDescription)"
        }
    }
}
