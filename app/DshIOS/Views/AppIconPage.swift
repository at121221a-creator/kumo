import SwiftUI
import UIKit

/// The home-screen icons people can pick (issue #170). iOS only switches between icons built into
/// the app, so there is no picture of one's own; the Apple Watch app keeps the main icon.
/// The plain ones are for people who would rather not have an illustrated character on the home
/// screen: the whales, and the app's name set in type. The pictures come from docs/design/brand:
/// make-icons.py (the mascot's colours, and the image-model ones kept in generated/),
/// make-drawn-icons.swift and make-wordmark-icons.swift (drawn in code). All are listed in
/// app/project.yml (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES).
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard = "Default", pink = "Pink", mint = "Mint", violet = "Violet", sticker = "Sticker"
    case geometric = "Geometric", pixel = "Pixel", whale = "Whale"
    case wordPixel = "WordPixel", wordPoster = "WordPoster", wordMono = "WordMono"

    var id: Self { self }

    static let illustrated: [AppIconChoice] = [.standard, .pink, .mint, .violet, .sticker]
    static let plain: [AppIconChoice] = [.geometric, .pixel, .whale]
    static let wordmarks: [AppIconChoice] = [.wordPixel, .wordPoster, .wordMono]

    /// The icon set's name for iOS; nil is the main icon.
    var iconName: String? { self == .standard ? nil : "AppIcon-\(rawValue)" }

    /// App icon sets cannot be loaded as images, so each has a small copy for this page.
    var preview: String { "AppIconPreview/\(rawValue)" }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "大肥鱼"
        case .pink: "樱花粉"
        case .mint: "薄荷绿"
        case .violet: "葡萄紫"
        case .sticker: "贴纸"
        case .geometric: "几何鲸鱼"
        case .pixel: "像素鲸鱼"
        case .whale: "小鲸鱼"
        case .wordPixel: "像素字标"
        case .wordPoster: "海报字标"
        case .wordMono: "终端字标"
        }
    }

    static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .standard
    }

    static var available: Bool { UIApplication.shared.supportsAlternateIcons }
}

/// The Settings row: the icon in use, read again on coming back from the page.
struct AppIconRow: View {
    @State private var current = AppIconChoice.current

    var body: some View {
        LabeledContent {
            Text(current.title).lineLimit(1)
        } label: {
            Label("App 图标", systemImage: "app.badge")
        }
        .onAppear { current = AppIconChoice.current }
    }
}

struct AppIconPage: View {
    @State private var current = AppIconChoice.current
    @State private var failure: String?

    var body: some View {
        List {
            Section("插画") {
                ForEach(AppIconChoice.illustrated) { row($0) }
            }
            Section("简洁") {
                ForEach(AppIconChoice.plain) { row($0) }
            }
            Section {
                ForEach(AppIconChoice.wordmarks) { row($0) }
            } header: {
                Text("字标")
            } footer: {
                Text("更换后，iOS 会弹出一次提示。Apple Watch 上的图标不会变。")
            }
        }
        .navigationTitle("App 图标")
        .navigationBarTitleDisplayMode(.inline)
        .alert("没能更换图标", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("好") {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func row(_ choice: AppIconChoice) -> some View {
        Button { pick(choice) } label: {
            HStack(spacing: 14) {
                Image(choice.preview)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .clipShape(.rect(cornerRadius: 13.5, style: .continuous))
                    // The pale icons would melt into a light page without an edge.
                    .overlay(RoundedRectangle(cornerRadius: 13.5, style: .continuous).strokeBorder(Palette.ink.opacity(0.08), lineWidth: 0.5))
                    .accessibilityHidden(true)
                Text(choice.title).foregroundStyle(Palette.ink)
                Spacer()
                if choice == current { Image(systemName: "checkmark").foregroundStyle(Palette.ink) }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(choice == current ? .isSelected : [])
        .groupedRow()
    }

    private func pick(_ choice: AppIconChoice) {
        guard choice != current else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.iconName)
                current = choice
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
