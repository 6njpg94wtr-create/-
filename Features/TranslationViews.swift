import SwiftUI
import NaturalLanguage
import UIKit

@MainActor
struct TranslationView: View {
    @Environment(\.dismiss) private var dismiss
    var isPresentedModally = false
    @StateObject private var controller = TranslationController()
    @ObservedObject private var history = TranslationHistoryStore.shared
    @ObservedObject private var playback = SpeechPlayback.shared
    @AppStorage("russianwords.translation.endpoint") private var endpoint = ""
    @State private var text = ""
    @State private var language: TranslationLanguage = .chinese
    @State private var style: TranslationStyle = .natural
    @State private var showFavorites = false
    @State private var detectionMessage: String?

    private var visibleHistory: [TranslationRecord] {
        history.records.filter { !showFavorites || $0.isFavorite }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("把想说的话，准确地说出来")
                        .font(.title2.bold())
                    endpointNotice
                    RWCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Picker("原文语言", selection: $language) {
                                    ForEach(TranslationLanguage.allCases) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                Button {
                                    language = language.opposite
                                } label: {
                                    Image(systemName: "arrow.left.arrow.right")
                                }
                                .accessibilityLabel("交换翻译方向")
                                Text(language.opposite.title).foregroundColor(.secondary)
                            }
                            TextEditor(text: $text)
                                .rwTextInput()
                                .frame(minHeight: 140)
                                .accessibilityLabel("需要翻译的原文")
                                .overlay(alignment: .topLeading) {
                                    if text.isEmpty {
                                        Text("输入中文或俄语…")
                                            .foregroundColor(.secondary)
                                            .padding(.top, 16).padding(.leading, 13)
                                            .allowsHitTesting(false)
                                    }
                                }
                            HStack {
                                Text("\(text.count) / 5,000").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button("识别语言", action: detectLanguage)
                                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button {
                                    playback.speak(text, language: language.speechLocale)
                                } label: { Image(systemName: "speaker.wave.2") }
                                    .disabled(text.isEmpty)
                                    .accessibilityLabel("朗读原文")
                            }
                            if let message = detectionMessage {
                                Text(message).font(.caption).foregroundColor(.secondary)
                            }
                            Picker("表达方式", selection: $style) {
                                ForEach(TranslationStyle.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Button {
                                controller.translate(text: text, language: language, style: style, endpoint: endpoint)
                            } label: {
                                HStack {
                                    if controller.isLoading { ProgressView() }
                                    Text(controller.isLoading ? "正在翻译…" : "翻译成\(language.opposite.title)")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.isLoading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if controller.isLoading { Button("取消请求") { controller.cancel() } }
                        }
                    }

                    if let error = controller.errorMessage { TranslationErrorLabel(message: error) }
                    if let error = playback.errorMessage { TranslationErrorLabel(message: error) }
                    if let error = history.storageError { TranslationErrorLabel(message: error) }
                    if let result = controller.result {
                        TranslationResultCard(record: currentRecord(result))
                    }
                    HStack {
                        Text("翻译记录").font(.title3.bold())
                        Spacer()
                        Toggle("仅收藏", isOn: $showFavorites).fixedSize()
                    }
                    if visibleHistory.isEmpty {
                        RWNotice(title: showFavorites ? "还没有收藏译文" : "还没有翻译记录", message: showFavorites ? "收藏译文后，可在这里随时重温。" : "完成一次翻译后，原文和译文会保存在本机。")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleHistory) { record in
                                TranslationResultCard(record: record)
                            }
                        }
                    }
                }
                .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
            .background(RWTheme.background.ignoresSafeArea())
            .navigationTitle("中俄翻译")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isPresentedModally { Button("关闭") { dismiss() } }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: TranslationSettingsView()) {
                        Image(systemName: "gearshape")
                    }.accessibilityLabel("翻译设置")
                }
            }
        }
        .navigationViewStyle(.stack)
        .tint(RWTheme.accent)
        .onDisappear { controller.cancel() }
    }

    @ViewBuilder private var endpointNotice: some View {
        if endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            RWNotice(title: "尚未连接翻译服务", message: "请点击右上角设置，配置兼容的在线翻译服务。", icon: "network")
        }
    }

    private func detectLanguage() {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .some(.russian): language = .russian; detectionMessage = "识别为俄语，你可以手动调整。"
        case .some(.simplifiedChinese), .some(.traditionalChinese): language = .chinese; detectionMessage = "识别为中文，你可以手动调整。"
        default: detectionMessage = "无法可靠识别，请手动选择中文或俄语。"
        }
    }

    private func currentRecord(_ record: TranslationRecord) -> TranslationRecord {
        history.records.first(where: { $0.id == record.id }) ?? record
    }
}

@MainActor
struct ConversationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = SpeechRecorder()
    @StateObject private var controller = TranslationController()
    @ObservedObject private var history = TranslationHistoryStore.shared
    @ObservedObject private var playback = SpeechPlayback.shared
    @AppStorage("russianwords.translation.endpoint") private var endpoint = ""
    @AppStorage("russianwords.speech.rate") private var rate = 0.4
    @State private var language: TranslationLanguage = .chinese
    @State private var recordingTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("面对面，轮流说一句")
                        .font(.title2.bold())
                    Text("点选说话语言，结束录音后检查文字，再翻译并朗读。")
                        .font(.subheadline).foregroundColor(.secondary)
                    if endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        RWNotice(title: "尚未连接翻译服务", message: "请点击右上角设置，配置兼容的在线翻译服务。", icon: "network")
                    }
                    HStack(spacing: 12) {
                        microphoneButton(.chinese)
                        microphoneButton(.russian)
                    }
                    if recorder.isRecording || recorder.isPreparing {
                        HStack {
                            ProgressView()
                            Text(recorder.isPreparing ? "正在准备麦克风…" : "正在听\(language.title)…")
                            Spacer()
                            Button("结束录音") { stopRecording() }
                        }.font(.subheadline)
                    }
                    RWCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("当前文字语言", selection: $language) {
                                ForEach(TranslationLanguage.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented)
                                .disabled(recorder.isRecording || recorder.isPreparing || controller.isLoading)
                            TextEditor(text: $recorder.transcript)
                                .rwTextInput()
                                .frame(minHeight: 110)
                                .accessibilityLabel("识别文字，可手动修改")
                            Text("可手动修改识别文字，也可以直接输入。")
                                .font(.caption).foregroundColor(.secondary)
                            HStack {
                                Text("语速").font(.subheadline)
                                Slider(value: $rate, in: 0.25...0.6, step: 0.05)
                                    .accessibilityLabel("译文朗读语速")
                                Button { playback.stop() } label: {
                                    Image(systemName: "stop.circle")
                                }.accessibilityLabel("停止朗读")
                            }
                            Button {
                                stopRecording()
                                controller.translate(text: recorder.transcript, language: language, style: .natural,
                                                     endpoint: endpoint, isConversation: true, playbackRate: Float(rate))
                            } label: {
                                HStack {
                                    if controller.isLoading { ProgressView() }
                                    Text(controller.isLoading ? "正在翻译…" : "翻译并朗读\(language.opposite.title)")
                                }.frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.isLoading || recorder.isRecording || recorder.isPreparing || recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if controller.isLoading { Button("取消翻译") { controller.cancel() } }
                        }
                    }
                    if let error = recorder.errorMessage { TranslationErrorLabel(message: error) }
                    if let error = controller.errorMessage { TranslationErrorLabel(message: error) }
                    if let error = playback.errorMessage { TranslationErrorLabel(message: error) }
                    if let error = history.storageError { TranslationErrorLabel(message: error) }
                    Text("对话记录").font(.title3.bold())
                    if history.records.filter(\.isConversation).isEmpty {
                        RWNotice(title: "还没有对话记录", message: "完成的双语对话会保存在这里，可随时重播。")
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(history.records.filter(\.isConversation)) { record in
                            TranslationResultCard(record: record)
                        }
                    }
                    Text("语音识别可能需要联网并由 Apple 处理音频；翻译文字会发送到你配置的服务。")
                        .font(.footnote).foregroundColor(.secondary)
                }.padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
            .background(RWTheme.background.ignoresSafeArea())
            .navigationTitle("双人对话")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: TranslationSettingsView()) { Image(systemName: "gearshape") }
                        .accessibilityLabel("翻译设置")
                }
            }
        }
        .navigationViewStyle(.stack)
        .tint(RWTheme.accent)
        .onDisappear {
            stopRecording()
            controller.cancel()
            playback.stop()
        }
        .onChange(of: scenePhase) { phase in
            // Permission prompts may make the scene inactive; they must not cancel
            // the authorization flow. Only leaving for the background cancels it.
            if phase == .background {
                stopRecording()
                controller.cancel()
                playback.stop()
            }
        }
    }

    private func microphoneButton(_ choice: TranslationLanguage) -> some View {
        Button {
            stopRecording()
            controller.cancel()
            language = choice
            recordingTask = Task { await recorder.start(language: choice) }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "mic.fill").font(.title2)
                Text("\(choice.title)发言").font(.headline)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 22)
        }
        .buttonStyle(.borderedProminent)
        .tint(choice == .chinese ? RWTheme.accent : RWTheme.blue)
        .disabled(recorder.isPreparing)
    }

    private func stopRecording() {
        recordingTask?.cancel()
        recordingTask = nil
        recorder.stop()
    }
}

@MainActor
struct TranslationSettingsView: View {
    @AppStorage("russianwords.translation.endpoint") private var endpoint = ""
    @State private var editedEndpoint = ""
    @State private var feedback: String?
    @State private var isSuccess = false

    var body: some View {
        Form {
            Section(header: Text("在线翻译服务"), footer: Text("需要兼容的 HTTPS 翻译服务地址。保存地址不代表服务已经通过连接验证。")) {
                TextField("https://你的服务/translate", text: $editedEndpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .accessibilityLabel("翻译接口地址")
                Button("保存地址") {
                    do {
                        let url = try HTTPTranslationService.validatedEndpoint(editedEndpoint)
                        endpoint = url.absoluteString
                        editedEndpoint = endpoint
                        feedback = "地址已保存。请返回翻译页输入一句话进行连接验证。"
                        isSuccess = true
                    } catch {
                        feedback = error.localizedDescription
                        isSuccess = false
                    }
                }
                if !endpoint.isEmpty {
                    Button("断开当前服务", role: .destructive) {
                        endpoint = ""
                        editedEndpoint = ""
                        feedback = "已断开，已有翻译记录仍保留。"
                        isSuccess = true
                    }
                }
                if let feedback = feedback {
                    Text(feedback).font(.footnote).foregroundColor(isSuccess ? .secondary : .red)
                }
            }
            Section(header: Text("数据与隐私")) {
                Text("原文会通过 HTTPS 发送到你配置的服务。翻译历史和收藏保存在本机。使用前请确认服务提供者的数据处理方式。")
                Text("App 不提供默认的翻译服务器。厂商 API 密钥应由服务端保管，请勿把密钥填入接口地址。")
                Text("语音识别使用 Apple Speech，中文和俄语识别的可用性受设备、系统和网络影响。")
            }
        }
        .rwFormStyle()
        .navigationTitle("翻译设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { editedEndpoint = endpoint }
    }
}

@MainActor
private struct TranslationResultCard: View {
    let record: TranslationRecord
    @ObservedObject private var history = TranslationHistoryStore.shared
    @ObservedObject private var playback = SpeechPlayback.shared
    @AppStorage("russianwords.speech.rate") private var rate = 0.4
    @State private var copied = false

    var body: some View {
        RWCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(record.sourceLanguage.title) → \(record.sourceLanguage.opposite.title)")
                        .font(.caption.weight(.semibold)).foregroundColor(RWTheme.accent)
                    Spacer()
                    Text(record.date, style: .date).font(.caption).foregroundColor(.secondary)
                }
                Text(record.original).foregroundColor(.secondary).textSelection(.enabled)
                Text(record.translation).font(.title3.weight(.medium)).textSelection(.enabled)
                if let explanation = record.explanation, !explanation.isEmpty {
                    Text(explanation).font(.subheadline).foregroundColor(.secondary)
                }
                HStack(spacing: 20) {
                    Button {
                        playback.speak(record.translation, language: record.sourceLanguage.opposite.speechLocale, rate: Float(rate))
                    } label: { Label("朗读", systemImage: "speaker.wave.2") }
                    Button {
                        UIPasteboard.general.string = record.translation
                        copied = true
                    } label: { Label(copied ? "已复制" : "复制", systemImage: "doc.on.doc") }
                    Spacer(minLength: 0)
                    Button { history.toggleFavorite(record.id) } label: {
                        Image(systemName: record.isFavorite ? "star.fill" : "star")
                    }.accessibilityLabel(record.isFavorite ? "取消收藏" : "收藏译文")
                }.font(.subheadline)
            }
        }
    }
}

private struct TranslationErrorLabel: View {
    let message: String
    var body: some View {
        RWNotice(title: "暂时无法完成", message: message, icon: "exclamationmark.triangle")
            .accessibilityLabel(message)
    }
}
