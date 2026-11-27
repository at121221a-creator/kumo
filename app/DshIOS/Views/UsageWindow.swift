import SwiftUI

/// 对话页里的一张用量窗口：每秒刷新一次，回复进行中显示计时。
/// 整张卡片按住就能拖到屏幕任何位置，位置记住；✕ 收掉，设置里能再打开。
struct UsageWindow: View {
    let model: SessionModel

    @AppStorage("xidai.usage.hidden") private var hidden = false
    @AppStorage("xidai.usage.x") private var savedX: Double = 0
    @AppStorage("xidai.usage.y") private var savedY: Double = 0

    @GestureState private var drag: CGSize = .zero
    @State private var startedAt: Date?

    private let width: CGFloat = 152

    var body: some View {
        GeometryReader { proxy in
            if !hidden {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    card(now: context.date)
                        .position(
                            x: clamp(origin(proxy).x + drag.width, lo: width / 2 + 8, hi: proxy.size.width - width / 2 - 8),
                            y: clamp(origin(proxy).y + drag.height, lo: 90, hi: proxy.size.height - 80)
                        )
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .updating($drag) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    let start = origin(proxy)
                                    savedX = Double(clamp(start.x + value.translation.width,
                                                          lo: width / 2 + 8, hi: proxy.size.width - width / 2 - 8))
                                    savedY = Double(clamp(start.y + value.translation.height,
                                                          lo: 90, hi: proxy.size.height - 80))
                                }
                        )
                }
            }
        }
        .onChange(of: model.running) { _, running in
            startedAt = running ? Date() : nil
        }
    }

    private func origin(_ proxy: GeometryProxy) -> CGPoint {
        let x = savedX <= 0 ? proxy.size.width - width / 2 - 12 : CGFloat(savedX)
        let y = savedY <= 0 ? 220 : CGFloat(savedY)
        return CGPoint(x: x, y: y)
    }

    private func clamp(_ value: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        min(max(value, lo), max(lo, hi))
    }

    private func card(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("本场用量")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 6)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { hidden = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            line("输入", UsageTally.tokens(model.tokens.input))
            line("缓存", UsageTally.tokens(model.tokens.cacheRead))
            line("输出", UsageTally.tokens(model.tokens.output))
            if let context = model.contextTokens {
                line("上下文", UsageTally.tokens(context))
            }

            Rectangle().fill(Palette.stroke).frame(height: 1).padding(.vertical, 2)

            HStack(spacing: 4) {
                Text("约").foregroundStyle(Palette.secondary)
                Spacer(minLength: 4)
                Text(UsageTally.money(UsageTally.cost(model.tokens)))
                    .foregroundStyle(Palette.ink)
            }
            .font(.system(size: 11, weight: .semibold))

            HStack(spacing: 3) {
                if model.running, let startedAt {
                    Circle()
                        .fill(Palette.running)
                        .frame(width: 4, height: 4)
                    Text("运行中 " + UsageTally.clock(now.timeIntervalSince(startedAt)))
                } else {
                    Text("更新 " + UsageTally.stamp(now))
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 9))
            .foregroundStyle(Palette.faint)
        }
        .padding(11)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.background.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.13), radius: 11, y: 4)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.secondary)
            Spacer(minLength: 6)
            Text(value).foregroundStyle(Palette.ink)
        }
        .font(.system(size: 10.5))
    }
}

enum UsageTally {
    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1000 { return String(format: "%.1fk", Double(value) / 1000) }
        return "\(value)"
    }

    static func cost(_ tokens: (input: Int, output: Int, cacheRead: Int)) -> Double {
        let fresh = max(0, tokens.input - tokens.cacheRead)
        return Double(fresh) / 1_000_000 * 3
            + Double(tokens.cacheRead) / 1_000_000 * 0.025
            + Double(tokens.output) / 1_000_000 * 6
    }

    static func money(_ value: Double) -> String {
        if value < 0.01 { return "¥0" }
        return String(format: "¥%.2f", value)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
