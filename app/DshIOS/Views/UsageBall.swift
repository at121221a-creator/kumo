import SwiftUI

/// 会话右下角一枚可拖动的用量胶囊：本场 token 与大致花费。
/// 点开看明细，长按隐藏，位置拖过就记住。
struct UsageBall: View {
    let model: SessionModel

    @AppStorage("xidai.ball.hidden") private var hidden = false
    @AppStorage("xidai.ball.x") private var savedX: Double = 0
    @AppStorage("xidai.ball.y") private var savedY: Double = 0

    @GestureState private var dragOffset: CGSize = .zero
    @State private var expanded = false

    var body: some View {
        GeometryReader { proxy in
            if !hidden {
                ZStack(alignment: .topLeading) {
                    if expanded {
                        panel
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.trailing, 12)
                            .padding(.top, 206)
                    }
                    capsule
                        .position(x: clamped(point(proxy).x + dragOffset.width, lo: 46, hi: proxy.size.width - 46),
                                  y: clamped(point(proxy).y + dragOffset.height, lo: 92, hi: proxy.size.height - 34))
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    let p = point(proxy)
                                    savedX = Double(clamped(p.x + value.translation.width, lo: 46, hi: proxy.size.width - 46))
                                    savedY = Double(clamped(p.y + value.translation.height, lo: 92, hi: proxy.size.height - 34))
                                }
                        )
                        .onTapGesture { withAnimation(.snappy(duration: 0.18)) { expanded.toggle() } }
                        .onLongPressGesture(minimumDuration: 0.6) {
                            withAnimation(.snappy(duration: 0.18)) { hidden = true }
                        }
                }
            }
        }
    }

    private func point(_ proxy: GeometryProxy) -> CGPoint {
        let x = savedX <= 0 ? proxy.size.width - 52 : CGFloat(savedX)
        let y = savedY <= 0 ? proxy.size.height - 120 : CGFloat(savedY)
        return CGPoint(x: x, y: y)
    }

    private func clamped(_ value: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        min(max(value, lo), max(lo, hi))
    }

    /// 胶囊本体：纯色底 + 细描边，拖动时不重算材质，所以顺。
    private var capsule: some View {
        UsageCapsule(model: model)
            .contentShape(Capsule())
            .accessibilityLabel("本场用量")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("本场用量")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy(duration: 0.18)) { expanded = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                }
                .buttonStyle(.plain)
            }
            line("输入", UsageFormat.tokens(model.tokens.input))
            line("其中缓存", UsageFormat.tokens(model.tokens.cacheRead))
            line("输出", UsageFormat.tokens(model.tokens.output))
            if let context = model.contextTokens {
                line("上下文", UsageFormat.tokens(context))
            }
            Rectangle().fill(Palette.stroke).frame(height: 1).padding(.vertical, 2)
            HStack(spacing: 4) {
                Text("约").foregroundStyle(Palette.secondary)
                Text(UsageFormat.money(UsageFormat.cost(model.tokens))).foregroundStyle(Palette.ink)
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(11)
        .frame(width: 152, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Palette.background.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 1)
                )
        )
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

/// 只有这一小块读 token：数字变化时只重画它，胶囊的形状和位置不动。
private struct UsageCapsule: View {
    let model: SessionModel

    var body: some View {
        HStack(spacing: 5) {
            Text(UsageFormat.tokens(model.tokens.input + model.tokens.output))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Rectangle()
                .fill(Palette.stroke)
                .frame(width: 1, height: 10)
            Text(UsageFormat.money(UsageFormat.cost(model.tokens)))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Palette.background.opacity(0.94))
                .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        )
    }
}

enum UsageFormat {
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
