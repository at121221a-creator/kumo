import SwiftUI

/// 对话页里一个可自由拖动的用量窗口：本场 token、上下文和大概花销。
/// 用纯色卡片而不是磨砂材质，拖动时不会每帧重绘。
struct UsageWindow: View {
    let model: SessionModel

    @AppStorage("xidai.usage.hidden") private var hidden = false
    @AppStorage("xidai.usage.x") private var savedX: Double = 0
    @AppStorage("xidai.usage.y") private var savedY: Double = 0

    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            if !hidden {
                card
                    .position(
                        x: clamp(point(proxy).x + dragOffset.width, lo: 92, hi: proxy.size.width - 92),
                        y: clamp(point(proxy).y + dragOffset.height, lo: 116, hi: proxy.size.height - 96)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                let origin = point(proxy)
                                savedX = Double(clamp(origin.x + value.translation.width, lo: 92, hi: proxy.size.width - 92))
                                savedY = Double(clamp(origin.y + value.translation.height, lo: 116, hi: proxy.size.height - 96))
                            }
                    )
            }
        }
    }

    private func point(_ proxy: GeometryProxy) -> CGPoint {
        let x = savedX <= 0 ? proxy.size.width - 100 : CGFloat(savedX)
        let y = savedY <= 0 ? 230 : CGFloat(savedY)
        return CGPoint(x: x, y: y)
    }

    private func clamp(_ value: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        min(max(value, lo), max(lo, hi))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                Text("本场用量")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 6)
                Button {
                    withAnimation(.snappy(duration: 0.18)) { hidden = true }
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

            Rectangle()
                .fill(Palette.stroke)
                .frame(height: 1)
                .padding(.vertical, 2)

            HStack(spacing: 4) {
                Text("约").foregroundStyle(Palette.secondary)
                Spacer(minLength: 4)
                Text(UsageTally.money(UsageTally.cost(model.tokens)))
                    .foregroundStyle(Palette.ink)
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(11)
        .frame(width: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.background.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
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
