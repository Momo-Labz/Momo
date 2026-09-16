import AppKit
import AVFoundation
import Speech
import SwiftUI

@MainActor
final class VoiceInput: ObservableObject {
    static let shared = VoiceInput()
    static let startTimeoutSeconds: TimeInterval = 20

    enum State: String {
        case ready = "READY"
        case permission = "ALLOW MICROPHONE"
        case starting = "STARTING"
        case listening = "LISTENING"
        case finished = "DRAFT READY"
        case unavailable = "VOICE UNAVAILABLE"
    }

    @Published private(set) var state: State = .ready
    @Published private(set) var text = ""
    @Published private(set) var level: Double = 0
    @Published private(set) var message = "Audio stays on this Mac. Nothing is sent to a provider."
    @Published private(set) var mode: ShortcutAction = .talk

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var startTimeoutTask: Task<Void, Never>?
    private var tapped = false
    private var generation = UUID()
    private var lastSpeech = Date()
    private var started = Date()
    private var destination: AgentSession?
    private var provider: AIProvider = .codex
    private var startInFlight = false

    init() {}

    /// Listening / permission / engine bring-up — blocks repeat Talk presses.
    var isActive: Bool {
        state == .listening || state == .permission || state == .starting
    }

    var isPendingStart: Bool { startInFlight || state == .permission || state == .starting }

    func prepare(_ mode: ShortcutAction) {
        // Do not cancel an in-flight system permission dialog — that causes re-prompts.
        if state == .permission || state == .starting || startInFlight { return }
        stop()
        self.mode = mode
        text = ""
        state = .ready
        destination = QuickAskContext.shared.session
        provider = QuickAskContext.shared.provider
        message = "Audio stays on this Mac. Nothing is sent to a provider."
    }

    func start() async {
        // Debounce: ignore repeat shortcut / mic taps while permission or start is pending.
        guard !startInFlight, !isActive else { return }
        startInFlight = true
        defer { startInFlight = false }

        let token = UUID()
        generation = token
        armStartTimeout(token: token)

        if let micBlock = VoicePermission.microphoneBlockReason() {
            fail(VoicePermission.settingsGuidance(for: micBlock))
            return
        }

        let needsMicPrompt = !VoicePermission.microphoneAuthorized()
        if needsMicPrompt {
            state = .permission
            message = "Waiting for Microphone access…"
        } else {
            state = .starting
            message = "Starting microphone…"
        }

        // Yield so SwiftUI can paint permission/starting before the system sheet appears.
        await Task.yield()

        let mic = await VoicePermission.requestMicrophoneIfNeeded()
        guard generation == token else { return }
        if let micBlock = VoicePermission.microphoneBlockReason() {
            fail(VoicePermission.settingsGuidance(for: micBlock))
            return
        }
        guard mic else {
            fail(VoicePermission.settingsGuidance(for: .microphoneDenied))
            return
        }

        if let speechBlock = VoicePermission.speechBlockReason() {
            fail(VoicePermission.settingsGuidance(for: speechBlock))
            return
        }
        let needsSpeechPrompt = SFSpeechRecognizer.authorizationStatus() == .notDetermined
        if needsSpeechPrompt {
            state = .permission
            message = "Waiting for Speech Recognition access…"
            await Task.yield()
        } else {
            state = .starting
            message = "Preparing on-device speech…"
        }

        let speech = await VoicePermission.requestSpeechIfNeeded()
        guard generation == token else { return }
        if let speechBlock = VoicePermission.speechBlockReason() {
            fail(VoicePermission.settingsGuidance(for: speechBlock))
            return
        }
        guard speech == .authorized else {
            fail(VoicePermission.settingsGuidance(for: .speechDenied))
            return
        }

        state = .starting
        message = "Connecting microphone…"
        await Task.yield()

        let audio: AudioStartResult
        do {
            // AVAudioEngine inputNode / start can stall if done on MainActor after a permission grant.
            audio = try await Self.installAudioPipeline(generation: token)
        } catch {
            fail("The microphone could not start. Check your audio input.")
            return
        }
        guard generation == token else {
            Self.teardownAudio(engine: audio.engine, tapped: true)
            return
        }

        engine = audio.engine
        request = audio.request
        tapped = true
        text = ""

        guard let recognizer = SFSpeechRecognizer(locale: .current),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            Self.teardownAudio(engine: audio.engine, tapped: true)
            engine = nil
            request = nil
            tapped = false
            fail("On-device speech is unavailable for this Mac or language. Use typed input; no cloud fallback is used.")
            return
        }

        recognition = recognizer.recognitionTask(with: audio.request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let result {
                    let recognized = result.bestTranscription.formattedString
                    if self.text != recognized { self.lastSpeech = .now }
                    self.text = recognized
                    if self.mode == .handsFree, Self.hasDraftCommand(recognized) {
                        self.text = Self.removingDraftCommand(recognized)
                        self.stop()
                        self.useDraft()
                        return
                    }
                    if self.mode == .handsFree, Self.hasStopCommand(recognized) {
                        self.text = Self.removingStopCommand(recognized)
                        self.stop()
                        return
                    }
                    if result.isFinal { self.stop(); return }
                }
                if error != nil {
                    self.fail("Recognition ended. Your partial draft is kept. Try again or type.")
                }
            }
        }

        clearStartTimeout()
        state = .listening
        started = .now
        lastSpeech = .now
        message = mode == .handsFree
            ? "Say “MOMO stop” to finish or “MOMO use draft” to open your draft. Up to 55 seconds."
            : mode == .talk
                ? "Speak naturally. Silence sends your question to MOMO."
                : "Press Stop or your shortcut again to finish."
        MomoFeedback.listenStart()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening else { return }
                if Date().timeIntervalSince(self.started) >= 55
                    || (self.mode == .talk && !self.text.isEmpty && Date().timeIntervalSince(self.lastSpeech) >= 2) {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        let wasActive = isActive
        clearStartTimeout()
        generation = UUID()
        timer?.invalidate()
        timer = nil
        recognition?.cancel()
        recognition = nil
        request?.endAudio()
        request = nil
        if let engine {
            Self.teardownAudio(engine: engine, tapped: tapped)
        }
        engine = nil
        tapped = false
        level = 0
        startInFlight = false
        if wasActive {
            state = text.isEmpty ? .ready : .finished
            message = text.isEmpty
                ? "No speech captured. Try again or type."
                : (mode == .talk ? "Sending to MOMO…" : "Review your words, then use them in your draft.")
            MomoFeedback.listenEnd()
        }
    }

    private func fail(_ reason: String) {
        clearStartTimeout()
        let keepMessage = reason
        stop()
        state = .unavailable
        message = keepMessage
    }

    private func armStartTimeout(token: UUID) {
        clearStartTimeout()
        startTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.startTimeoutSeconds))
            guard let self, !Task.isCancelled, self.generation == token else { return }
            guard self.state == .permission || self.state == .starting else { return }
            self.fail("Talk timed out while starting the microphone. Try again, or type your question.")
        }
    }

    private func clearStartTimeout() {
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
    }

    private struct AudioStartResult {
        let engine: AVAudioEngine
        let request: SFSpeechAudioBufferRecognitionRequest
    }

    /// Build + start AVAudioEngine off the main actor to avoid UI freezes after permission grants.
    private nonisolated static func installAudioPipeline(generation: UUID) async throws -> AudioStartResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AudioStartResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let engine = AVAudioEngine()
                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true
                    request.requiresOnDeviceRecognition = true
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else {
                        throw AudioPipelineError.noInput
                    }
                    input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                        request.append(buffer)
                        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                        var energy: Float = 0
                        for i in 0..<Int(buffer.frameLength) { energy += channel[i] * channel[i] }
                        let amplitude = min(1, Double(sqrt(energy / Float(buffer.frameLength))) * 8)
                        Task { @MainActor in
                            let voice = VoiceInput.shared
                            guard voice.generation == generation else { return }
                            voice.level = amplitude
                        }
                    }
                    engine.prepare()
                    try engine.start()
                    continuation.resume(returning: AudioStartResult(engine: engine, request: request))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func teardownAudio(engine: AVAudioEngine, tapped: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            engine.stop()
            if tapped { engine.inputNode.removeTap(onBus: 0) }
        }
    }

    private enum AudioPipelineError: Error { case noInput }

    func useDraft() {
        stop()
        if let destination { QuickAskContext.shared.select(destination) }
        else { QuickAskContext.shared.newChat(); QuickAskContext.shared.provider = provider }
        let existing = QuickAskContext.shared.draft
        QuickAskContext.shared.draft = existing + (existing.isEmpty || text.isEmpty ? "" : "\n") + text
        text = ""
        state = .ready
        message = "Added to your draft. The microphone is off."
        NotificationCenter.default.post(name: .showCommandPalette, object: nil)
    }

    static func hasDraftCommand(_ text: String) -> Bool {
        text.range(of: #"\bmomo\s+use\s+draft[.!?]*\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func removingDraftCommand(_ text: String) -> String {
        text.replacingOccurrences(of: #"\bmomo\s+use\s+draft[.!?]*\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func hasStopCommand(_ text: String) -> Bool {
        text.range(of: #"\bmomo\s+stop[.!?]*\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func removingStopCommand(_ text: String) -> String {
        text.replacingOccurrences(of: #"\bmomo\s+stop[.!?]*\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
enum MomoFeedback {
    static func perform() {
        guard UserDefaults.standard.object(forKey: "hapticFeedback") as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func shortcutPressed() {
        perform()
        guard soundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    static func listenStart() {
        perform()
        guard soundEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    static func listenEnd() {
        guard soundEnabled else { return }
        NSSound(named: "Purr")?.play()
    }

    static func thinkStart() {
        guard soundEnabled else { return }
        NSSound(named: "Submarine")?.play()
    }

    private static var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "momoAlertSoundEnabled.v1") as? Bool ?? true
    }
}

struct VoicePopup: View {
    var embedded = false

    private func leave() {
        if embedded { MomoSurface.shared.show(.sessions) } else { dismiss() }
    }
    @ObservedObject var voice = VoiceInput.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AnimatedMomoMark(size: 46, animated: voice.state == .listening, motion: .wave)
                VStack(alignment: .leading, spacing: 5) {
                    Text("MOMO / \(voice.mode.title.uppercased())").font(BarBoyStyle.sectionLabel)
                    Text(voice.state.rawValue).font(.headline).foregroundStyle(voice.isActive ? BarBoyStyle.coral : Color.primary)
                }
                Spacer()
                Image(systemName: voice.state == .finished ? "checkmark.circle.fill" : "mic.fill").foregroundStyle(BarBoyStyle.coral)
            }
            HStack(spacing: 4) {
                ForEach(0..<19) { index in
                    Rectangle().fill(BarBoyStyle.coral)
                        .frame(width: 10, height: 32)
                        .scaleEffect(x: 1, y: reduceMotion ? 0.3 : max(0.08, voice.level * (index % 3 == 0 ? 1 : 0.65)), anchor: .center)
                }
            }.frame(maxWidth: .infinity).accessibilityHidden(true)
            ScrollView { Text(voice.text.isEmpty ? voice.message : voice.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(height: 100)
            if !voice.text.isEmpty { Text(voice.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Close") { voice.stop(); leave() }.barBoyButton()
                Spacer()
                Button(voice.isActive ? "Stop" : "Start listening") {
                    if voice.isActive { voice.stop() } else { Task { await voice.start() } }
                }.barBoyButton()
                Button("Use draft") { voice.useDraft(); leave() }.barBoyButton().disabled(voice.text.isEmpty || voice.isActive)
            }
        }.padding(22).frame(width: embedded ? nil : 420).frame(maxWidth: embedded ? .infinity : nil).background(BarBoyStyle.panel)
            .onDisappear { voice.stop() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                if (notification.object as? NSWindow)?.title == "MOMO Voice" { voice.stop() }
            }
    }
}
