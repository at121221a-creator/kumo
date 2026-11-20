import SwiftUI

/// 对话页里的一张用量窗口：本场 token、上下文和大概花销。
/// 整张卡片按住就能拖到屏幕任何位置，位置记住；✕ 收掉，设置里能再打开。
struct UsageWindow: View {
    let model: SessionModel

    @AppStorage("xidai.usage.hidden") private var hidden = false
    @AppStorage("xidai.usage.x") private var savedX: Double = 0
    @AppStorage("xidai.usage.y") private var savedY: Double = 0

    @GestureState private var drag: CGSize = .zero

    private let width: CGFloat = 152

    var body: some View {
        GeometryReader { proxy in
            if !hidden {
                card
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

    private func origin(_ proxy: GeometryProxy) -> CGPoint {
        let x = savedX <= 0 ? proxy.size.width - width / 2 - 12 : CGFloat(savedX)
        let y = savedY <= 0 ? 220 : CGFloat(savedY)
        return CGPoint(x: x, y: y)
    }

    private func clamp(_ value: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        min(max(value, lo), max(lo, hi))
    }

    private var card: some View {
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
}
