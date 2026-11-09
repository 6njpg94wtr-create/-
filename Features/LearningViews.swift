import SwiftUI

@MainActor
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingQuickTranslation = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    HStack(spacing: 12) {
                        metric("连续学习", value: "\(model.streak)", suffix: "天", icon: "flame.fill")
                        metric("到期复习", value: "\(model.dueCount)", suffix: "词", icon: "clock.arrow.circlepath")
                    }
                    RWSectionHeading(title: "先学会用，再慢慢扩展", subtitle: "三层词汇体系 · 按自己的节奏学习")
                    PriorityCards()
                    NavigationLink(destination: LibraryView(scope: .all)) {
                        Label("查询俄语、中文或变化词形", systemImage: "magnifyingglass")
                            .font(.headline).frame(maxWidth: .infinity).padding(18)
                            .background(RWTheme.surface).clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    if let error = model.errorMessage {
                        RWNotice(title: "需要处理", message: error, icon: "exclamationmark.triangle")
                    }
                }
                .padding(20).frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .background(RWTheme.background.ignoresSafeArea())
            .navigationTitle("RussianWords")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingQuickTranslation = true } label: {
                        Image(systemName: "character.bubble").accessibilityLabel("快速翻译")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingQuickTranslation) { TranslationView(isPresentedModally: true) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TODAY · 今日学习").font(.caption.weight(.bold)).tracking(1.5)
            Text("每天一点，\n在生活中用起来。")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("今日学习记录").font(.subheadline)
                Spacer()
                Text("\(model.todayCount) / \(model.dailyGoal)").font(.headline.monospacedDigit())
            }
            ProgressView(value: Double(min(model.todayCount, model.dailyGoal)), total: Double(max(model.dailyGoal, 1)))
                .tint(.white)
            NavigationLink(destination: ReviewView()) {
                HStack {
                    Text(model.dueCount > 0 ? "复习到期单词" : "开始今日学习").font(.headline)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(RWTheme.accent).padding(16)
                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .foregroundColor(.white).padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RWTheme.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func metric(_ title: String, value: String, suffix: String, icon: String) -> some View {
        RWCard {
            Label(title, systemImage: icon).font(.caption).foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title.weight(.bold)).monospacedDigit()
                Text(suffix).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

@MainActor
struct PriorityCards: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            priority(scope: .core, target: "1,000", title: "入门核心词", caption: "先学基本交流、购物、宿舍与学校用语", actual: "可学习 \(model.stats.core) 词", icon: "leaf.fill", color: .green)
            priority(scope: .basic, target: "3,000", title: "基础常用词", caption: "包含入门 1,000 词，逐步连接语法与情景表达", actual: "可学习 \(model.stats.basic) 词", icon: "books.vertical.fill", color: RWTheme.accent)
            priority(scope: .reference, target: "30,000+", title: "扩展查询库", caption: "遇到再查，用于阅读与专业词汇积累；无需全部背诵", actual: "查询库实际 \(model.stats.total) 条", icon: "text.book.closed.fill", color: RWTheme.blue)
        }
    }

    private func priority(scope: LibraryScope, target: String, title: String, caption: String, actual: String, icon: String, color: Color) -> some View {
        NavigationLink(destination: LibraryView(scope: scope)) {
            RWCard {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: icon).font(.title2).foregroundColor(color)
                        .frame(width: 42, height: 42).background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(target).font(.title2.weight(.bold)).foregroundColor(color)
                            Text("目标").font(.caption2).foregroundColor(.secondary)
                        }
                        Text(title).font(.headline)
                        Text(caption).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(actual).font(.caption.weight(.semibold)).foregroundColor(color)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
struct LearningHubView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    RWSectionHeading(title: "建立自己的俄语基础", subtitle: "先掌握常用词，再把它们用进真实表达")
                    PriorityCards()
                    RWSectionHeading(title: "我的学习工具", subtitle: "查询、收藏与复习记录保存在本机")
                    tool("今日课程", subtitle: "查看 Day 1 示例课程与完成记录", icon: "calendar", destination: DailyCourseView())
                    tool("开始练习", subtitle: "两道示例题 · 选择与输入练习", icon: "checkmark.square", destination: ExerciseView())
                    tool("词典查询", subtitle: "原形、变化词形与重音无关搜索", icon: "magnifyingglass", destination: LibraryView(scope: .all))
                    tool("我的收藏", subtitle: "\(model.favorites.count) 个关注的词条", icon: "star.fill", destination: LibraryView(scope: .favorites))
                    tool("我的单词", subtitle: "保留旧版单词，也可以添加自己的中俄词汇", icon: "square.and.pencil", destination: PersonalWordsView())
                    tool("记忆复习", subtitle: "\(model.dueCount) 个到期单词 · 按记忆情况安排下次复习", icon: "rectangle.stack.fill", destination: ReviewView())
                    RWNotice(title: "学习词与查询词分开", message: "只有具备中文释义并完成审校的核心与基础词，才会自动进入新词计划。扩展查询词不会因收藏就自动加入背诵。")
                }
                .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
            .background(RWTheme.background.ignoresSafeArea())
            .navigationTitle("学习")
        }
        .navigationViewStyle(.stack)
    }

    private func tool<Destination: View>(_ title: String, subtitle: String, icon: String, destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            RWCard {
                HStack(spacing: 14) {
                    Image(systemName: icon).font(.title2).foregroundColor(RWTheme.accent).frame(width: 32)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }.foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    let scope: LibraryScope

    private var title: String {
        switch scope {
        case .all: return "词典查询"
        case .core: return "入门核心词"
        case .basic: return "基础常用词"
        case .reference: return "扩展查询库"
        case .favorites: return "我的收藏"
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if scope == .core || scope == .basic {
                    RWNotice(title: scope == .core ? "目标 1,000 个入门词" : "目标 3,000 个基础词", message: "列表只展示已审校、具有中文释义的学习词。基础词库包含入门核心词，数量不会重复相加。")
                } else if scope != .favorites {
                    RWNotice(title: "按需查询，不要求全部背诵", message: "开放词典当前以英文释义为主。词条会明确显示释义语言与审校状态；专业词汇请结合可靠专业资料核对。")
                }
                if model.isLoading {
                    ProgressView("正在查询…").padding(24)
                } else if model.results.isEmpty {
                    emptyState
                } else {
                    ForEach(model.results) { entry in
                        NavigationLink(destination: EntryDetailView(entry: entry)) {
                            entryRow(entry)
                        }.buttonStyle(.plain)
                    }
                    Text("为保持查询流畅，仅显示当前查询的一部分结果；输入更具体的词可缩小范围。")
                        .font(.caption).foregroundColor(.secondary).padding(.vertical, 8)
                }
                if let error = model.errorMessage {
                    RWNotice(title: "查询提示", message: error, icon: "exclamationmark.triangle")
                }
            }
            .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .background(RWTheme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "俄语、中文、英文或变化词形")
        .onChange(of: query) { value in
            model.searchText = value
            model.search()
        }
        .onAppear {
            model.selectedScope = scope
            model.searchText = query
            model.search()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass").font(.system(size: 36)).foregroundColor(RWTheme.accent)
            Text(query.isEmpty ? "这里还没有词条" : "没有找到匹配词条").font(.headline)
            Text(emptyMessage).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }

    private var emptyMessage: String {
        if !query.isEmpty { return "尝试俄语原形或更短的关键词。暂缺中文释义的词，无法通过中文搜索找到。" }
        switch scope {
        case .core, .basic: return "中文学习词正在等待可靠选词与审校。目标数量不代表已经收录，可以先使用扩展词典查询。"
        case .favorites: return "在词条详情里点收藏，方便下次快速找到。"
        default: return "词典数据尚未加载。请查看下方提示。"
        }
    }

    private func entryRow(_ entry: DictionaryEntry) -> some View {
        RWCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.displayWord(showStress: model.showStress)).font(.title3.weight(.semibold)).foregroundColor(.primary)
                    Text(entry.translation).font(.subheadline).foregroundColor(.secondary).lineLimit(3)
                    Text(entry.chinese.isEmpty ? "英文释义" : "中文释义")
                        .font(.caption2.weight(.semibold)).foregroundColor(RWTheme.accent)
                }
                Spacer(minLength: 8)
                Image(systemName: model.isFavorite(entry.id) ? "star.fill" : "chevron.right")
                    .foregroundColor(model.isFavorite(entry.id) ? .yellow : .secondary)
                    .font(.caption)
            }
        }
    }
}

@MainActor
struct EntryDetailView: View {
    @EnvironmentObject private var model: AppModel
    let entry: DictionaryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RWCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(entry.displayWord(showStress: model.showStress))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .textSelection(.enabled)
                        if !entry.partOfSpeech.isEmpty {
                            Text(entry.partOfSpeech).font(.subheadline).foregroundColor(.secondary)
                        }
                        Text(model.mastery(for: entry.id).title).font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 18) {
                            Button { model.speak(entry.russian) } label: {
                                Label("听发音", systemImage: "speaker.wave.2.fill")
                            }
                            Button { model.toggleFavorite(entry) } label: {
                                Label(model.isFavorite(entry.id) ? "已收藏" : "收藏", systemImage: model.isFavorite(entry.id) ? "star.fill" : "star")
                            }
                        }
                        .font(.subheadline.weight(.semibold)).tint(RWTheme.accent)
                    }
                }
                RWCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(entry.chinese.isEmpty ? "英文释义" : "中文释义").font(.headline)
                        Text(entry.translation).textSelection(.enabled)
                        if !entry.chinese.isEmpty && !entry.english.isEmpty {
                            Divider()
                            Text(entry.english).font(.subheadline).foregroundColor(.secondary)
                        }
                        if !entry.gender.isEmpty { Text("性别：\(entry.gender)").font(.subheadline) }
                        if !entry.aspect.isEmpty { Text("动词体：\(entry.aspect)").font(.subheadline) }
                    }
                }
                if entry.reviewStatus != "verified" {
                    RWNotice(title: "待审校词条", message: "本词条来自开放词典，尚未通过本项目教学审校。重音与释义请结合来源核对；未提供中文释义时，不会自动进入中文新词学习计划。")
                }
                RWCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("自主练习").font(.headline)
                        Text("你可以主动把这个词加入自己的复习队列。主动选择不会改变词条的审校状态，也不计入已审校中文核心词。")
                            .font(.caption).foregroundColor(.secondary)
                        Button {
                            model.enroll(entry)
                        } label: {
                            Label(model.isEnrolled(entry.id) ? "已加入自主练习" : "加入自主练习", systemImage: model.isEnrolled(entry.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent).tint(RWTheme.accent)
                        .disabled(model.isEnrolled(entry.id))
                    }
                }
                RWCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("来源与许可").font(.headline)
                        Text(entry.source.isEmpty ? "来源尚未记录" : entry.source).font(.caption).textSelection(.enabled)
                        Text(entry.license.isEmpty ? "许可尚未记录" : entry.license).font(.caption).foregroundColor(.secondary)
                        Text(entry.reviewStatus == "verified" ? "教学审校：已完成" : "教学审校：待完成")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .background(RWTheme.background.ignoresSafeArea())
        .navigationTitle("词条详情").navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var answerVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let entry = model.reviewEntries.first {
                    HStack {
                        Text("本轮剩余 \(model.reviewEntries.count) 词").font(.subheadline)
                        Spacer()
                        Label("间隔复习", systemImage: "clock.arrow.circlepath").font(.caption).foregroundColor(.secondary)
                    }
                    Text(model.mastery(for: entry.id).title).font(.caption).foregroundColor(.secondary)
                    RWCard {
                        VStack(spacing: 24) {
                            Text(entry.displayWord(showStress: model.showStress))
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .multilineTextAlignment(.center)
                            Button { model.speak(entry.russian) } label: {
                                Label("听发音", systemImage: "speaker.wave.2.fill")
                            }
                            if answerVisible {
                                Divider()
                                Text(entry.translation).font(.title3).multilineTextAlignment(.center)
                            } else {
                                Button("查看释义") { withAnimation { answerVisible = true } }
                                    .buttonStyle(.borderedProminent).tint(RWTheme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                    }
                    if answerVisible {
                        Text("刚才记得怎么样？").font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            rating("忘记了", rating: .again, color: .red, entry: entry)
                            rating("有点难", rating: .hard, color: .orange, entry: entry)
                            rating("记得", rating: .good, color: RWTheme.blue, entry: entry)
                            rating("很轻松", rating: .easy, color: .green, entry: entry)
                        }
                    }
                    Text("评分后安排下次复习。学习记录会保留在本机。")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle").font(.system(size: 52)).foregroundColor(RWTheme.accent)
                        Text("当前没有待学习单词").font(.title2.weight(.bold))
                        Text("到期复习会优先出现，其次是已审校的中文核心词和基础词。扩展查询库不会自动加入。")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        NavigationLink("去查询词典", destination: LibraryView(scope: .all))
                            .buttonStyle(.borderedProminent).tint(RWTheme.accent)
                    }.padding(.vertical, 42)
                }
                if let error = model.errorMessage {
                    RWNotice(title: "学习记录提示", message: error, icon: "exclamationmark.triangle")
                }
            }
            .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .background(RWTheme.background.ignoresSafeArea())
        .navigationTitle("记忆复习").navigationBarTitleDisplayMode(.inline)
        .onAppear { model.prepareReview() }
        .onChange(of: model.reviewEntries.first?.id) { _ in answerVisible = false }
    }

    private func rating(_ title: String, rating: ReviewRating, color: Color, entry: DictionaryEntry) -> some View {
        Button { model.rate(entry, rating: rating) } label: {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(16)
                .foregroundColor(color).background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

@MainActor
struct ProfileView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RWCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("我的学习节奏", systemImage: "slider.horizontal.3").font(.headline)
                            Stepper("每日目标：\(model.dailyGoal) 词", value: Binding(get: { model.dailyGoal }, set: { model.updateDailyGoal($0) }), in: 1...100)
                            Toggle("显示俄语重音", isOn: $model.showStress).tint(RWTheme.accent)
                        }
                    }
                    RWCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("真实内容统计").font(.headline)
                            countRow("查询词条", model.stats.total)
                            countRow("含中文释义", model.stats.chinese)
                            countRow("已审校词条", model.stats.verified)
                            countRow("收藏词条", model.favorites.count)
                            countRow("已保留的旧版个人词条", model.legacyCount)
                            Text("数量来自当前词典和本机学习记录。1,000 / 3,000 / 30,000+ 是内容目标，基础 3,000 包含核心 1,000。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    NavigationLink(destination: TranslationSettingsView()) {
                        RWCard {
                            HStack {
                                Label("翻译服务设置", systemImage: "network")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.font(.headline).foregroundColor(.primary)
                        }
                    }.buttonStyle(.plain)
                    NavigationLink(destination: PersonalWordsView()) {
                        RWCard {
                            HStack {
                                Label("我的单词", systemImage: "square.and.pencil")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.font(.headline).foregroundColor(.primary)
                        }
                    }.buttonStyle(.plain)
                    NavigationLink(destination: ProgressBackupView()) {
                        RWCard {
                            HStack {
                                Label("备份与恢复", systemImage: "externaldrive")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.font(.headline).foregroundColor(.primary)
                        }
                    }.buttonStyle(.plain)
                    RWNotice(title: "离线与在线", message: "已收录的词典、收藏与学习记录可离线使用。翻译需要配置真实服务并联网；语音识别是否可离线取决于设备和系统语言支持。")
                    RWCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("开放数据与审校").font(.headline)
                            Text("扩展词典采用 OpenRussian 开放数据，按 CC BY-SA 4.0 使用与署名。来源词条不等同于已审校的中文教学内容。")
                                .font(.subheadline).foregroundColor(.secondary)
                            Link("查看原始词典项目", destination: URL(string: "https://github.com/Badestrand/russian-dictionary")!)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
            .background(RWTheme.background.ignoresSafeArea())
            .navigationTitle("我的")
        }
        .navigationViewStyle(.stack)
    }

    private func countRow(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text("\(count)").font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}
