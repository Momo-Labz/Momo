import AppKit
import AVFoundation
import Speech
import SwiftUI

@MainActor
final class VoiceInput: ObservableObject {
    static let shared = VoiceInput()
    enum State: String { case ready = "READY", permission = "ALLOW MICROPHONE", listening = "LISTENING", finished = "DRAFT READY", unavailable = "VOICE UNAVAILABLE" }
    @Published private(set) var state: State = .ready
    @Published private(set) var text = ""
    @Published private(set) var level: Double = 0
    @Published private(set) var message = "Audio stays on this Mac. Nothing is sent to a provider."
    @Published private(set) var mode: ShortcutAction = .talk
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var tapped = false
    private var generation = UUID()
    private var lastSpeech = Date()
    private var started = Date()
    private var destination: AgentSession?
    private var provider: AIProvider = .codex
    init() {}

    var isActive: Bool { state == .listening || state == .permission }

    func prepare(_ mode: ShortcutAction) {
        stop(); self.mode = mode; text = ""; state = .ready
        destination = QuickAskContext.shared.session; provider = QuickAskContext.shared.provider
        message = "Audio stays on this Mac. Nothing is sent to a provider."
    }
    func start() async {
        guard !isActive else { return }
        let token = UUID(); generation = token; state = .permission
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == token else { return }
        guard mic else { fail("Allow Microphone access in macOS System Settings → Privacy & Security."); return }
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard generation == token else { return }
        guard speech == .authorized else { fail("Allow Speech Recognition in macOS System Settings → Privacy & Security."); return }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            fail("On-device speech is unavailable for this Mac or language. Use typed input; no cloud fallback is used."); return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true; request.requiresOnDeviceRecognition = true
        self.request = request; text = ""
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { fail("No microphone input is available."); return }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var energy: Float = 0
            for i in 0..<Int(buffer.frameLength) { energy += channel[i] * channel[i] }
            let amplitude = min(1, Double(sqrt(energy / Float(buffer.frameLength))) * 8)
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.level = amplitude
            }
        }
        tapped = true
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let result {
                    let recognized = result.bestTranscription.formattedString
                    if self.text != recognized { self.lastSpeech = .now }
                    self.text = recognized
                    if self.mode == .handsFree, Self.hasDraftCommand(recognized) {
                        self.text = Self.removingDraftCommand(recognized); self.stop(); self.useDraft(); return
                    }
                    if self.mode == .handsFree, Self.hasStopCommand(recognized) {
                        self.text = Self.removingStopCommand(recognized); self.stop(); return
                    }
                    if result.isFinal { self.stop(); return }
                }
                if error != nil { self.fail("Recognition ended. Your partial draft is kept. Try again or type.") }
            }
        }
        do { engine.prepare(); try engine.start() } catch { fail("The microphone could not start. Check your audio input."); return }
        state = .listening; started = .now; lastSpeech = .now
        message = mode == .handsFree ? "Say “MOMO stop” to finish or “MOMO use draft” to open your draft. Up to 55 seconds." : mode == .talk ? "Speak naturally. A pause finishes your draft." : "Press Stop or your shortcut again to finish."
        MomoFeedback.perform()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening else { return }
                if Date().timeIntervalSince(self.started) >= 55 || (self.mode == .talk && !self.text.isEmpty && Date().timeIntervalSince(self.lastSpeech) >= 2) { self.stop() }
            }
        }
    }
    func stop() {
        let wasActive = isActive
        generation = UUID(); timer?.invalidate(); timer = nil
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil; level = 0
        if wasActive { state = text.isEmpty ? .ready : .finished; message = text.isEmpty ? "No speech captured. Try again or type." : "Review your words, then use them in your draft."; MomoFeedback.perform() }
    }
    private func fail(_ reason: String) { stop(); state = .unavailable; message = reason }
    func useDraft() {
        stop()
        if let destination { QuickAskContext.shared.select(destination) }
        else { QuickAskContext.shared.newChat(); QuickAskContext.shared.provider = provider }
        let existing = QuickAskContext.shared.draft
        QuickAskContext.shared.draft = existing + (existing.isEmpty || text.isEmpty ? "" : "\n") + text
        text = ""; state = .ready; message = "Added to your draft. The microphone is off."
        NotificationCenter.default.post(name: .showCommandPalette, object: nil)
    }
    static func hasDraftCommand(_ text: String) -> Bool { text.range(of: #"\bmomo\s+use\s+draft[.!?]*\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil }
    static func removingDraftCommand(_ text: String) -> String { text.replacingOccurrences(of: #"\bmomo\s+use\s+draft[.!?]*\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines) }
    static func hasStopCommand(_ text: String) -> Bool { text.range(of: #"\bmomo\s+stop[.!?]*\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil }
    static func removingStopCommand(_ text: String) -> String { text.replacingOccurrences(of: #"\bmomo\s+stop[.!?]*\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines) }
}

@MainActor
enum MomoFeedback {
    static func perform() {
        guard UserDefaults.standard.object(forKey: "hapticFeedback") as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

struct VoicePopup: View {
    /// Rendered inside the MOMO window rather than a window of its own.
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
