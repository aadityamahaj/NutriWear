import Foundation
import Speech
import AVFoundation

/// Speech-to-text (ask the coach aloud) and text-to-speech (spoken replies).
/// Works in the Simulator for synthesis; recognition needs mic access.
@MainActor
final class SpeechService: NSObject, ObservableObject {

    @Published var isListening = false
    @Published var transcript = ""
    @Published var isSpeaking = false
    @Published var authorized = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        // IMPORTANT: the permission callbacks fire on background queues. Under
        // Swift 6, resuming a continuation captured in a @MainActor method from
        // that background queue triggers an executor-isolation check that traps
        // (EXC_BREAKPOINT). We therefore request permissions via `nonisolated`
        // free helpers that carry NO actor isolation, then update @Published
        // state back on the main actor.
        let speechStatus = await Self.requestSpeechStatus()
        let micGranted = await Self.requestMicPermission()

        authorized = (speechStatus == .authorized) && micGranted
        if !authorized {
            errorMessage = "Enable microphone and speech recognition in Settings to ask aloud."
        }
    }

    private nonisolated static func requestSpeechStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    private nonisolated static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Listening

    func startListening() {
        guard authorized, !isListening else { return }

        // The recognizer can be nil (locale unsupported) or temporarily
        // unavailable (no network for server-based recognition, device busy).
        // Without this check recognitionTask is a silent no-op and the user
        // sees "listening" but nothing is ever transcribed.
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now. Check your connection and try again."
            return
        }

        transcript = ""
        errorMessage = nil

        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use the default mode (NOT .measurement). .measurement disables the
            // system's input signal processing, which starves the speech
            // recognizer of usable audio and is the main reason spoken words
            // weren't being understood. .spokenAudio is tuned for dictation.
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Prefer server recognition (more accurate); fall back to on-device
            // automatically when offline if the device supports it.
            request.requiresOnDeviceRecognition = false
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            // Guard against an invalid hardware format (common on Simulator with
            // no input route) — installing a tap with 0 channels/sampleRate
            // triggers an AVAudioEngine abort. Bail gracefully instead.
            guard format.channelCount > 0, format.sampleRate > 0 else {
                errorMessage = "No microphone input available here. Type your question instead."
                self.request = nil
                return
            }
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in self.transcript = result.bestTranscription.formattedString }
                }
                if let error {
                    Task { @MainActor in
                        // Surface a real failure instead of silently stopping, so
                        // the user knows nothing was understood.
                        if self.transcript.isEmpty {
                            self.errorMessage = "Didn't catch that: \(error.localizedDescription)"
                        }
                        self.stopListening()
                    }
                } else if result?.isFinal ?? false {
                    Task { @MainActor in self.stopListening() }
                }
            }
        } catch {
            errorMessage = "Couldn't start listening: \(error.localizedDescription)"
            stopListening()
        }
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Speaking

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        // On device, route through playback so TTS is audible.
        #if !targetEnvironment(simulator)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
