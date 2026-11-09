import SwiftUI

@MainActor
struct ExerciseView: View {
    @EnvironmentObject private var model: AppModel
    private let questions = ExampleExercises.questions
    @State private var store: ExerciseStore?
    @State private var index = 0
    @State private var answer = ""
    @State private var grade: ExerciseGrade?
    @State private var errorMessage: String?
    @State private var attempts = 0
    @State private var correct = 0
    @State private var mistakeCount = 0
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RWNotice(title: "两道示例练习", message: "体验选择题、输入题及错题保存。示例不代表完整题库，作答不会自动提高单词掌握状态。")
                Text("累计作答 \(attempts) 次 · 正确 \(correct) 次 · 历史错题 \(mistakeCount) 道")
                    .font(.caption).foregroundColor(.secondary)
                if isLoading { ProgressView("正在加载练习…") }
                if questions.indices.contains(index) {
                    questionCard(questions[index])
                } else {
                    RWNotice(title: "暂无练习题", message: "当前没有可用的示例题。")
                }
                if let errorMessage {
                    RWNotice(title: "练习暂时无法完成", message: errorMessage, icon: "exclamationmark.triangle")
                    if store == nil { Button("重新加载", action: load).buttonStyle(.bordered) }
                }
            }
            .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .background(RWTheme.background.ignoresSafeArea()).tint(RWTheme.accent)
        .navigationTitle("开始练习").navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func questionCard(_ question: ExerciseQuestion) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            RWCard {
                Text("第 \(index + 1) / \(questions.count) 题 · \(question.type == .multipleChoice ? "选择题" : "输入题")")
                    .font(.caption.weight(.semibold)).foregroundColor(RWTheme.accent)
                Text(question.prompt).font(.title3.weight(.semibold))
                if question.type == .multipleChoice {
                    ForEach(question.options, id: \.id) { option in
                        Button { answer = option.id } label: {
                            HStack(alignment: .top) {
                                Image(systemName: answer == option.id ? "largecircle.fill.circle" : "circle")
                                Text(option.text).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).disabled(grade != nil || store == nil)
                    }
                } else {
                    TextField("输入俄语答案", text: $answer)
                        .textInputAutocapitalization(.never).disableAutocorrection(true)
                        .rwTextInput().disabled(grade != nil || store == nil)
                    Text("忽略首尾空格、大小写和重音；本示例严格区分 ё／е。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Button { submit(question) } label: {
                    Text("提交答案").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store == nil || grade != nil || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let grade {
                RWNotice(title: grade.isCorrect ? "回答正确" : "回答错误，已记录错题",
                         message: "正确答案：\(answerText(question))", icon: grade.isCorrect ? "checkmark.circle" : "exclamationmark.circle")
                if let explanation = question.explanation { Text(explanation).font(.body) }
                if index + 1 < questions.count {
                    Button("下一题") { move(to: index + 1) }.buttonStyle(.borderedProminent)
                } else {
                    RWNotice(title: "本轮示例练习已结束", message: "作答统计和错题已保存在本机。")
                    Button("重新练习") { move(to: 0) }.buttonStyle(.bordered)
                }
            }
        }
    }

    private func answerText(_ question: ExerciseQuestion) -> String {
        question.type == .multipleChoice
            ? question.options.first(where: { $0.id == question.correctAnswer })?.text ?? question.correctAnswer
            : question.correctAnswer
    }

    private func load() {
        isLoading = true; errorMessage = nil; store = nil
        defer { isLoading = false }
        do {
            for question in questions { try question.validate() }
            store = try model.makeExerciseStore()
            refreshCounts()
        } catch { errorMessage = error.localizedDescription }
    }

    private func submit(_ question: ExerciseQuestion) {
        guard grade == nil, let store else { return }
        do {
            let savedGrade = try store.submit(question, answer: answer)
            grade = savedGrade
            errorMessage = nil
            refreshCounts()
        } catch { errorMessage = error.localizedDescription }
    }

    private func move(to nextIndex: Int) { index = nextIndex; answer = ""; grade = nil; errorMessage = nil }
    private func refreshCounts() {
        attempts = store?.totalAttempts ?? 0
        correct = store?.correctAttempts ?? 0
        mistakeCount = store?.mistakes.count ?? 0
    }
}
