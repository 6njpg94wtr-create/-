import SwiftUI

@MainActor
struct DailyCourseView: View {
    @EnvironmentObject private var model: AppModel
    @State private var course: DailyCourse?
    @State private var status: DailyCourseStatus?
    @State private var store: CourseProgressStore?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isLoading { ProgressView("正在加载课程…").frame(maxWidth: .infinity) }
                if let course {
                    RWCard {
                        Text("Day \(course.dayNumber) · 约 \(course.estimatedMinutes) 分钟")
                            .font(.caption.weight(.semibold)).foregroundColor(RWTheme.accent)
                        Text(course.title).font(.title2.weight(.bold))
                        Text(course.learningGoal).font(.body)
                        Label(completionTitle, systemImage: status?.completionState == .completed ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline).foregroundColor(RWTheme.accent)
                    }
                    if course.isSample {
                        RWNotice(title: "Day 1 示例课程", message: "本课用于体验课程流程，内容尚待教学审校。Day 2～90 尚未提供。")
                    }
                    if course.requiredTasks.contains(.grammar) {
                        RWCard {
                            Text(course.grammarTopic).font(.headline)
                            Text(course.grammarExplanation).font(.body)
                        }
                    }
                    if !course.exampleSentences.isEmpty {
                        RWCard {
                            Text("例句").font(.headline)
                            ForEach(course.exampleSentences, id: \.id) { example in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(example.russian).font(.title3)
                                    Text(example.chinese).font(.body).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    RWCard {
                        Text("本课任务").font(.headline)
                        taskRow("新词学习 · \(course.vocabularyIDs.count) 词", kind: .newVocabulary)
                        taskRow("复习 · \(course.reviewIDs.count) 词", kind: .review)
                        taskRow("语法阅读", kind: .grammar)
                        taskRow("例句学习", kind: .examples)
                    }
                    Button(action: complete) {
                        Label(status?.completionState == .completed ? "今日课程已完成" : "完成今日课程", systemImage: "checkmark.circle")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store == nil || status?.completionState == .completed)
                    Text("此操作记录本课任务完成，不改变单词的 SM-2 调度或掌握状态。")
                        .font(.caption).foregroundColor(.secondary)
                } else if !isLoading && errorMessage == nil {
                    RWNotice(title: "暂无可用课程", message: "当前没有可加载的课程内容，不会自动生成缺失天数。")
                }
                if let errorMessage {
                    RWNotice(title: "课程暂时无法完成", message: errorMessage, icon: "exclamationmark.triangle")
                    Button("重新加载", action: load).buttonStyle(.bordered)
                }
            }
            .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .background(RWTheme.background.ignoresSafeArea()).tint(RWTheme.accent)
        .navigationTitle("今日课程").navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private var completionTitle: String {
        switch status?.completionState {
        case .completed: return "已完成"
        case .inProgress: return "进行中"
        default: return "尚未完成"
        }
    }

    private func taskRow(_ title: String, kind: CourseTaskKind) -> some View {
        let state = status?.state(for: kind) ?? .notStarted
        return HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(state == .notApplicable ? "本课未配置" : state == .completed ? "已完成" : "待完成")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func load() {
        isLoading = true; errorMessage = nil; store = nil; course = nil; status = nil
        defer { isLoading = false }
        do {
            let loader = try JSONCourseLoader.bundledSample()
            guard let day = loader.availableDays.first, let loaded = try loader.course(dayNumber: day) else { return }
            course = loaded
            let opened = try model.makeCourseProgressStore()
            status = try opened.status(for: loaded)
            store = opened
        } catch { errorMessage = error.localizedDescription }
    }

    private func complete() {
        guard let course, let store else { return }
        errorMessage = nil
        do {
            for task in CourseTaskKind.allCases where course.requiredTasks.contains(task) {
                try store.setTask(task, completed: true, for: course)
            }
            status = try store.status(for: course)
        } catch {
            status = try? store.status(for: course)
            errorMessage = error.localizedDescription
        }
    }
}
