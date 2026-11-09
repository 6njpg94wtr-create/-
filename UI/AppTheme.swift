import SwiftUI
import UIKit

enum RWTheme {
    static let accent = Color(red: 0.49, green: 0.40, blue: 0.95)
    static let blue = Color(red: 0.26, green: 0.53, blue: 0.98)
    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.05, blue: 0.10, alpha: 1)
            : UIColor(red: 0.95, green: 0.96, blue: 0.99, alpha: 1)
    })
    static let surface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.09, blue: 0.16, alpha: 1)
            : .secondarySystemGroupedBackground
    })
    static let gradient = LinearGradient(colors: [accent, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct RWCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RWTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(RWTheme.accent.opacity(0.10), lineWidth: 1))
    }
}

struct RWNotice: View {
    let title: String
    let message: String
    var icon: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundColor(RWTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RWTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct RWSectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.bold))
            Text(subtitle).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RWFormStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
                .background(RWTheme.background.ignoresSafeArea())
                .tint(RWTheme.accent)
        } else {
            // iOS 15 keeps its native adaptive Form/List background.
            content.tint(RWTheme.accent)
        }
    }
}

extension View {
    func rwFormStyle() -> some View { modifier(RWFormStyle()) }

    func rwTextInput() -> some View {
        self.font(.body).padding(8)
            .background(RWTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(RWTheme.accent.opacity(0.15), lineWidth: 1))
    }
}
