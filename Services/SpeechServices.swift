import AVFoundation
import Combine
import Foundation
import Speech
import UIKit

@MainActor
final class SpeechPlayback: ObservableObject {
    static let shared = SpeechPlayback()
    @Published private(set) var errorMessage: String?
    private let synthesizer = AVSpeechSynthesizer()
    private var lifecycleObserver: AnyCancellable?

    init() {
        lifecycleObserver = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification))
            .sink { [weak self] notification in
                let isBackground = notification.name == UIApplication.didEnterBackgroundNotification
                let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue == AVAudioSession.InterruptionType.began.rawValue
                guard isBackground || began else { return }
                Task { @MainActor [weak self] in self?.stop() }
            }
    }

    func speak(_ text: String, language: String = "ru-RU", rate: Float = 0.4) {
        errorMessage = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let voice = AVSpeechSynthesisVoice(language: language) else {
            errorMessage = "系统未提供所选语言的声音，请在 iPhone 设置中下载对应语音。"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            synthesizer.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = min(max(rate, 0.25), 0.6)
            synthesizer.speak(utterance)
        } catch {
            errorMessage = "无法开始朗读：\(error.localizedDescription)"
        }
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

@MainActor
final class SpeechRecorder: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var errorMessage: String?
    private let engine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var activeToken: UUID?
    private var lifecycleObserver: AnyCancellable?

    init() {
        lifecycleObserver = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification))
            .sink { [weak self] notification in
                let isBackground = notification.name == UIApplication.didEnterBackgroundNotification
                let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue == AVAudioSession.InterruptionType.began.rawValue
                guard isBackground || began else { return }
                Task { @MainActor [weak self] in
                    guard let self = self, self.isRecording || self.isPreparing else { return }
                    self.errorMessage = isBackground ? "录音已因进入后台停止，可以检查文字后重新录音。" : "录音被系统音频中断，可以检查文字后重新录音。"
                    self.stop()
                }
            }
    }

    func start(language: TranslationLanguage) async {
        guard !Task.isCancelled else { return }
        stop()
        SpeechPlayback.shared.stop()
        let token = UUID()
        activeToken = token
        isPreparing = true
        transcript = ""
        errorMessage = nil
        defer { if activeToken == token { isPreparing = false } }

        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard activeToken == token, !Task.isCancelled else { return }
        guard authorization == .authorized else {
            errorMessage = "请在系统设置中允许 RussianWords 使用语音识别。"
            return
        }
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard activeToken == token, !Task.isCancelled else { return }
        guard microphoneAllowed else {
            errorMessage = "请在系统设置中允许 RussianWords 使用麦克风。"
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.speechLocale)),
              recognizer.isAvailable else {
            errorMessage = "当前语言的语音识别暂不可用，请检查网络或改为输入文字。"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: [])
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                errorMessage = "未找到可用的麦克风，请使用 iPhone 真机重试。"
                stop()
                return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal ?? false
                let failure = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self = self, self.activeToken == token else { return }
                    if let text = text { self.transcript = text }
                    if let failure = failure {
                        self.errorMessage = "语音识别失败：\(failure)。可以编辑已识别文字后继续。"
                        self.stop()
                    } else if finished {
                        self.stop()
                    }
                }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            errorMessage = "无法开始录音：\(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        activeToken = nil
        isPreparing = false
        isRecording = false
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
