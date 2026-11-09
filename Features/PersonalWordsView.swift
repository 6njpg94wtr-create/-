import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct PersonalWordsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAdd = false
    @State private var search = ""
    private var filtered: [LegacyLearningWord] {
        let key = RussianSearch.normalize(search)
        return model.personalWords.filter { key.isEmpty || RussianSearch.normalize($0.russian + " " + $0.chinese).contains(key) }
    }
    var body: some View {
        List {
            Section {
                Text("自己的笔记与旧版词库保存在这里，不计入已审校的 1,000 / 3,000 教学词目标。新增单词会加入自主复习。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("我的单词 · \(model.personalWords.count)") {
                if filtered.isEmpty { Text("还没有匹配的单词，可点击右上角添加。").foregroundColor(.secondary) }
                ForEach(filtered) { word in
                    NavigationLink(destination: EntryDetailView(entry: model.entry(for: word))) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(word.russian).font(.headline)
                            Text(word.chinese).foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let snapshot = filtered
                    for index in offsets { model.deletePersonalWord(snapshot[index]) }
                }
            }
        }
        .navigationTitle("我的单词")
        .searchable(text: $search, prompt: "俄语或中文")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showAdd) { PersonalWordEditor() }
    }
}

@MainActor
private struct PersonalWordEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var russian = ""
    @State private var chinese = ""
    @State private var phonetic = ""
    var body: some View {
        NavigationView {
            Form {
                Section("自己的学习笔记") {
                    TextField("俄语单词或短句", text: $russian)
                    TextField("中文含义", text: $chinese)
                    TextField("发音笔记（选填）", text: $phonetic)
                }
            }
            .navigationTitle("添加我的单词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if model.addPersonalWord(russian: russian, chinese: chinese, phonetic: phonetic) { dismiss() }
                    }.disabled(russian.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.navigationViewStyle(.stack)
    }
}

struct ProgressDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
struct ProgressBackupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var exporting = false
    @State private var importing = false
    @State private var document = ProgressDocument(data: Data())
    @State private var pendingRestore: Data?
    @State private var confirmRestore = false
    var body: some View {
        Form {
            Section("学习记录") {
                Text("备份包括个人单词、收藏、复习记录和每日目标。内置词典独立保存；翻译与对话历史不包含在此备份中。")
                    .font(.callout).foregroundColor(.secondary)
                Button("导出学习备份") {
                    do { document = ProgressDocument(data: try model.exportProgress()); exporting = true }
                    catch { model.errorMessage = error.localizedDescription }
                }
                Button("从备份恢复") { importing = true }
            }
        }
        .navigationTitle("备份与恢复")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "RussianWords-progress") { result in
            if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size < 20_000_000 else { throw LearningStorageError.invalidData("备份文件超过 20 MB") }
                pendingRestore = try Data(contentsOf: url)
                confirmRestore = true
            } catch { model.errorMessage = error.localizedDescription }
        }
        .alert("替换当前学习记录？", isPresented: $confirmRestore) {
            Button("取消", role: .cancel) { pendingRestore = nil }
            Button("恢复", role: .destructive) {
                if let data = pendingRestore { model.restoreProgress(data) }
                pendingRestore = nil
            }
        } message: { Text("恢复会替换当前学习进度；替换前会在本机保存一份原记录。损坏或不兼容的备份将被拒绝。") }
    }
}
