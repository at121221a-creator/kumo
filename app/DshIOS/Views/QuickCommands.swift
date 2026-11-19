import SwiftUI

/// 一条快捷指令：一段常用话术，点一下填进输入框。
struct QuickCommand: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
}

@MainActor
final class QuickCommandStore: ObservableObject {
    static let shared = QuickCommandStore()

    @Published private(set) var items: [QuickCommand] = []

    private let key = "xidai.quickCommands"

    private init() {
        load()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([QuickCommand].self, from: data) {
            items = decoded
            return
        }
        items = [
            QuickCommand(text: "总结一下上面这段"),
            QuickCommand(text: "换成更短的表达"),
            QuickCommand(text: "列个步骤清单"),
            QuickCommand(text: "这段话翻译成英文"),
        ]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(QuickCommand(text: trimmed))
        save()
    }

    func remove(_ command: QuickCommand) {
        items.removeAll { $0.id == command.id }
        save()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        items.move(fromOffsets: offsets, toOffset: destination)
        save()
    }
}

/// 输入框上方那一排：点一下把话术填进草稿，不直接发。
struct QuickCommandBar: View {
    @ObservedObject private var store = QuickCommandStore.shared
    let insert: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.items) { command in
                    Button {
                        Haptics.soft()
                        insert(command.text)
                    } label: {
                        Text(Self.label(command.text))
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Palette.bubble.opacity(0.65)))
                            .foregroundStyle(Palette.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private static func label(_ text: String) -> String {
        let one = text.replacingOccurrences(of: "\n", with: " ")
        return one.count > 14 ? String(one.prefix(14)) + "…" : one
    }
}

struct QuickCommandSettingsPage: View {
    @ObservedObject private var store = QuickCommandStore.shared
    @State private var draft = ""

    var body: some View {
        List {
            Section {
                ForEach(store.items) { command in
                    Text(command.text)
                }
                .onDelete { offsets in
                    for index in offsets { store.remove(store.items[index]) }
                }
                .onMove { source, destination in
                    store.move(from: source, to: destination)
                }
            } header: {
                Text("快捷指令")
            } footer: {
                Text("点输入框上方那一排，文字会填进草稿，不会直接发出去。左滑删除。")
            }

            Section {
                HStack {
                    TextField("新的指令", text: $draft)
                    Button("添加") {
                        store.add(draft)
                        draft = ""
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("快捷指令")
        .navigationBarTitleDisplayMode(.inline)
    }
}
