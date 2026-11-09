import SwiftUI

@MainActor
struct MainAppView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        TabView {
            HomeView().tabItem { Label("首页", systemImage: "house.fill") }
            LearningHubView().tabItem { Label("学习", systemImage: "book.fill") }
            TranslationView().tabItem { Label("翻译", systemImage: "character.bubble.fill") }
            ConversationView().tabItem { Label("对话", systemImage: "mic.fill") }
            ProfileView().tabItem { Label("我的", systemImage: "person.fill") }
        }
        .tint(.indigo)
        .environmentObject(model)
        .task { model.reload() }
        .alert("暂时无法完成", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
