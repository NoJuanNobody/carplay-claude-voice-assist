import XCTest
@testable import CarPlayAssistant
import AVFoundation
import Combine

// MARK: - Mock Components

private final class MockVoiceCaptureEngine: VoiceCaptureEngine {
    var startCaptureCalled = false
    var stopCaptureCalled = false

    override func startCapture() throws {
        startCaptureCalled = true
    }

    override func stopCapture() {
        stopCaptureCalled = true
    }
}

private final class MockSpeechRecognizer: SpeechRecognizer {
    var startStreamingCalled = false
    var stopRecognitionCalled = false
    var appendBufferCalled = false

    override func startStreamingRecognition(locale: Locale = .current) throws {
        startStreamingCalled = true
    }

    override func stopRecognition() {
        stopRecognitionCalled = true
    }

    override func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        appendBufferCalled = true
    }
}

private final class MockTextToSpeech: TextToSpeech {
    var speakCalled = false
    var lastSpokenText: String?
    var stopSpeakingCalled = false

    override func speak(_ text: String, voice: VoiceConfig? = nil) {
        speakCalled = true
        lastSpokenText = text
    }

    override func stopSpeaking(at boundary: AVSpeechBoundary = .immediate) {
        stopSpeakingCalled = true
    }
}

private final class MockPCCClient: PCCClientProtocol {
    func isAvailable() -> Bool { return false }

    func processAudio(_ buffer: AVAudioPCMBuffer) async throws -> String {
        return "mock transcription"
    }
}

private final class MockPipelineDelegate: VoicePipelineDelegate {
    var stateChanges: [VoicePipelineState] = []
    var partialTexts: [String] = []
    var errors: [VoicePipelineError] = []

    func voicePipelineDidChangeState(_ state: VoicePipelineState) {
        stateChanges.append(state)
    }

    func voicePipelineDidReceivePartialText(_ text: String) {
        partialTexts.append(text)
    }

    func voicePipelineDidEncounterError(_ error: VoicePipelineError) {
        errors.append(error)
    }
}

// MARK: - VoicePipelineTests

final class VoicePipelineTests: XCTestCase {

    private var captureEngine: MockVoiceCaptureEngine!
    private var speechRecognizer: MockSpeechRecognizer!
    private var textToSpeech: MockTextToSpeech!
    private var pccClient: MockPCCClient!
    private var pipeline: VoicePipeline!
    private var delegate: MockPipelineDelegate!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        captureEngine = MockVoiceCaptureEngine()
        speechRecognizer = MockSpeechRecognizer()
        textToSpeech = MockTextToSpeech()
        pccClient = MockPCCClient()
        pipeline = VoicePipeline(
            captureEngine: captureEngine,
            speechRecognizer: speechRecognizer,
            textToSpeech: textToSpeech,
            pccClient: pccClient
        )
        delegate = MockPipelineDelegate()
        pipeline.delegate = delegate
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        pipeline = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - State Transition Tests

    func testInitialStateIsIdle() {
        XCTAssertEqual(pipeline.state, .idle)
    }

    func testActivateTransitionsToListening() {
        pipeline.activate()

        XCTAssertEqual(pipeline.state, .listening)
        XCTAssertTrue(captureEngine.startCaptureCalled)
        XCTAssertTrue(speechRecognizer.startStreamingCalled)
        XCTAssertEqual(delegate.stateChanges, [.listening])
    }

    func testActivateFromNonIdleStateReportsError() {
        // First activate to get to listening state
        pipeline.activate()
        delegate.errors.removeAll()
        delegate.stateChanges.removeAll()

        // Try to activate again
        pipeline.activate()

        XCTAssertEqual(pipeline.state, .listening)
        XCTAssertEqual(delegate.errors.count, 1)

        if case .invalidStateTransition(let from, let to) = delegate.errors.first {
            XCTAssertEqual(from, .listening)
            XCTAssertEqual(to, .listening)
        } else {
            XCTFail("Expected invalidStateTransition error")
        }
    }

    func testDeactivateTransitionsToIdle() {
        pipeline.activate()
        delegate.stateChanges.removeAll()

        pipeline.deactivate()

        XCTAssertEqual(pipeline.state, .idle)
        XCTAssertTrue(captureEngine.stopCaptureCalled)
        XCTAssertTrue(speechRecognizer.stopRecognitionCalled)
        XCTAssertTrue(textToSpeech.stopSpeakingCalled)
        XCTAssertEqual(delegate.stateChanges, [.idle])
    }

    func testDeactivateFromIdleStaysIdle() {
        pipeline.deactivate()

        // State was already idle, delegate should not be called since state didn't change
        XCTAssertEqual(pipeline.state, .idle)
    }

    func testSpeakTransitionsToSpeaking() {
        pipeline.speak("Hello, driver!")

        XCTAssertEqual(pipeline.state, .speaking)
        XCTAssertTrue(textToSpeech.speakCalled)
        XCTAssertEqual(textToSpeech.lastSpokenText, "Hello, driver!")
        XCTAssertEqual(delegate.stateChanges, [.speaking])
    }

    func testDidFinishSpeakingTransitionsToIdle() {
        pipeline.speak("Hello")
        delegate.stateChanges.removeAll()

        // Simulate TTS finishing
        pipeline.didFinishSpeaking()

        XCTAssertEqual(pipeline.state, .idle)
        XCTAssertEqual(delegate.stateChanges, [.idle])
    }

    // MARK: - State Publisher Tests

    func testStatePublisherEmitsStateChanges() {
        var publishedStates: [VoicePipelineState] = []

        pipeline.statePublisher
            .sink { state in
                publishedStates.append(state)
            }
            .store(in: &cancellables)

        pipeline.activate()
        pipeline.speak("Test")
        pipeline.didFinishSpeaking()

        // Initial .idle + .listening + .speaking + .idle
        XCTAssertEqual(publishedStates, [.idle, .listening, .speaking, .idle])
    }

    // MARK: - Process User Input Tests

    func testProcessUserInputFromNonListeningReturnsEmpty() async {
        let result = await pipeline.processUserInput()
        XCTAssertEqual(result, "")
    }

    func testProcessUserInputTransitionsToProcessing() async {
        pipeline.activate()
        delegate.stateChanges.removeAll()

        // Simulate speech recognition providing text
        pipeline.didRecognizeText("Navigate to the store", isFinal: false)

        let result = await pipeline.processUserInput()

        XCTAssertEqual(result, "Navigate to the store")
        XCTAssertEqual(pipeline.state, .processing)
        XCTAssertTrue(captureEngine.stopCaptureCalled)
        XCTAssertTrue(speechRecognizer.stopRecognitionCalled)
    }

    // MARK: - Pipeline Activation/Deactivation Cycle Tests

    func testFullActivateDeactivateCycle() {
        // Activate
        pipeline.activate()
        XCTAssertEqual(pipeline.state, .listening)

        // Deactivate
        pipeline.deactivate()
        XCTAssertEqual(pipeline.state, .idle)

        // Re-activate should work
        pipeline.activate()
        XCTAssertEqual(pipeline.state, .listening)

        // State changes: listening, idle, listening
        XCTAssertEqual(delegate.stateChanges, [.listening, .idle, .listening])
    }

    func testMultipleDeactivateCallsAreSafe() {
        pipeline.activate()
        pipeline.deactivate()
        pipeline.deactivate()
        pipeline.deactivate()

        XCTAssertEqual(pipeline.state, .idle)
    }

    // MARK: - VoicePipelineState Raw Values

    func testStateRawValues() {
        XCTAssertEqual(VoicePipelineState.idle.rawValue, "idle")
        XCTAssertEqual(VoicePipelineState.listening.rawValue, "listening")
        XCTAssertEqual(VoicePipelineState.processing.rawValue, "processing")
        XCTAssertEqual(VoicePipelineState.speaking.rawValue, "speaking")
    }
}
