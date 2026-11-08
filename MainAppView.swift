import SwiftUI
import AVFoundation
import Combine
import Foundation

// MARK: - 1. 数据模型
struct RussianWord: Identifiable, Codable, Hashable {
    let id: UUID
    var russian: String
    var phonetic: String
    var chinese: String
    var category: String
    var isMastered: Bool

    init(id: UUID = UUID(), russian: String, phonetic: String, chinese: String, category: String, isMastered: Bool = false) {
        self.id = id
        self.russian = russian
        self.phonetic = phonetic
        self.chinese = chinese
        self.category = category
        self.isMastered = isMastered
    }
}

// MARK: - 2. 数据存储管理
class WordStore: ObservableObject {
    @Published var words: [RussianWord] {
        didSet { saveToUserDefaults() }
    }

    private let saveKey = "perfect_russian_words_v10"

    init() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([RussianWord].self, from: data) {
            self.words = decoded
        } else {
            self.words = [
                RussianWord(russian: "Здравствуйте", phonetic: "zdráf-stvuy-te", chinese: "您好（正式）", category: "日常问候"),
                RussianWord(russian: "Спасибо", phonetic: "spa-sí-ba", chinese: "谢谢", category: "日常问候"),
                RussianWord(russian: "Пожалуйста", phonetic: "pa-zhá-luys-ta", chinese: "不客气 / 请", category: "日常问候"),
                RussianWord(russian: "Где такси?", phonetic: "gde tak-sí", chinese: "出租车在哪里？", category: "交通出行"),
                RussianWord(russian: "Сколько стоит?", phonetic: "skól'-ko stó-it", chinese: "多少钱？", category: "购物消费"),
                RussianWord(russian: "Больница", phonetic: "bol'-ní-tsa", chinese: "医院", category: "医疗生活")
            ]
        }
    }

    private func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(words) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    func addWord(russian: String, phonetic: String, chinese: String, category: String) {
        let newWord = RussianWord(russian: russian, phonetic: phonetic, chinese: chinese, category: category)
        words.insert(newWord, at: 0)
    }

    func deleteWords(at offsets: IndexSet) {
        words.remove(atOffsets: offsets)
    }

    func toggleMastered(for word: RussianWord) {
        if let index = words.firstIndex(where: { $0.id == word.id }) {
            words[index].isMastered.toggle()
        }
    }
}

// MARK: - 3. 语音播报服务
class SpeechManager {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(text: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.75
        synthesizer.speak(utterance)
    }
}

// MARK: - 4. 主视图入口
struct MainAppView: View {
    @StateObject private var wordStore = WordStore()

    var body: some View {
        TabView {
            WordListView(wordStore: wordStore)
                .tabItem {
                    Label("词库", systemImage: "book.fill")
                }

            FlashcardView(wordStore: wordStore)
                .tabItem {
                    Label("闪卡", systemImage: "rectangle.stack.fill")
                }
        }
    }
}

// MARK: - 5. 单词列表视图
struct WordListView: View {
    @ObservedObject var wordStore: WordStore
    @State private var searchText = ""
    @State private var showingAdd = false

    var filteredWords: [RussianWord] {
        if searchText.isEmpty {
            return wordStore.words
        } else {
            return wordStore.words.filter {
                $0.russian.localizedCaseInsensitiveContains(searchText) ||
                $0.chinese.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredWords) { word in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(word.russian).font(.headline)
                                if word.isMastered {
                                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                                }
                            }
                            Text("[\(word.phonetic)]").font(.subheadline).foregroundColor(.secondary)
                            Text(word.chinese).font(.body).foregroundColor(.blue)
                        }
                        Spacer()
                        Button(action: { SpeechManager.shared.speak(text: word.russian) }) {
                            Image(systemName: "speaker.wave.2.fill")
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            wordStore.toggleMastered(for: word)
                        } label: {
                            Label(word.isMastered ? "未掌握" : "已掌握", systemImage: word.isMastered ? "arrow.uturn.backward" : "checkmark")
                        }
                        .tint(word.isMastered ? .orange : .green)
                    }
                }
                .onDelete(perform: wordStore.deleteWords)
            }
            .searchable(text: $searchText, prompt: "搜索单词或中文...")
            .navigationTitle("俄语单词本")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAdd = true }) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddWordView(wordStore: wordStore)
            }
        }
    }
}

// MARK: - 6. 添加单词页面
struct AddWordView: View {
    @ObservedObject var wordStore: WordStore
    @Environment(\.presentationMode) var presentationMode

    @State private var russian = ""
    @State private var phonetic = ""
    @State private var chinese = ""
    @State private var category = "日常问候"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("单词信息")) {
                    TextField("俄语 (例: Привет)", text: $russian)
                    TextField("音标 (例: pri-vét)", text: $phonetic)
                    TextField("中文 (例: 你好)", text: $chinese)
                }
            }
            .navigationTitle("新增单词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if !russian.isEmpty && !chinese.isEmpty {
                            wordStore.addWord(russian: russian, phonetic: phonetic, chinese: chinese, category: category)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .disabled(russian.isEmpty || chinese.isEmpty)
                }
            }
        }
    }
}

// MARK: - 7. 闪卡背诵视图
struct FlashcardView: View {
    @ObservedObject var wordStore: WordStore
    @State private var currentIndex = 0
    @State private var isFlipped = false

    var body: some View {
        NavigationView {
            VStack {
                if wordStore.words.isEmpty {
                    Text("暂无单词").foregroundColor(.secondary)
                } else {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(.systemBackground))
                            .shadow(radius: 10)

                        VStack(spacing: 20) {
                            if !isFlipped {
                                Text(wordStore.words[currentIndex % wordStore.words.count].russian)
                                    .font(.system(size: 36, weight: .bold))
                                Text("[\(wordStore.words[currentIndex % wordStore.words.count].phonetic)]")
                                    .font(.title3).foregroundColor(.secondary)
                                Button("发音") {
                                    SpeechManager.shared.speak(text: wordStore.words[currentIndex % wordStore.words.count].russian)
                                }.padding(.top)
                            } else {
                                Text(wordStore.words[currentIndex % wordStore.words.count].chinese)
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(20)
                    }
                    .frame(height: 300)
                    .padding(.horizontal, 24)
                    .onTapGesture {
                        withAnimation { isFlipped.toggle() }
                    }

                    Spacer()

                    HStack(spacing: 50) {
                        Button("上一个") {
                            if currentIndex > 0 {
                                currentIndex -= 1
                                isFlipped = false
                            }
                        }.disabled(currentIndex == 0)

                        Text("\(currentIndex + 1) / \(wordStore.words.count)")

                        Button("下一个") {
                            if currentIndex < wordStore.words.count - 1 {
                                currentIndex += 1
                                isFlipped = false
                            }
                        }.disabled(currentIndex >= wordStore.words.count - 1)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("闪卡速记")
        }
    }
}
