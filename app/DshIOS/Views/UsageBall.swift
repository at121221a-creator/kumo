import SwiftUI

/// 会话里一颗可拖动的小球：显示这一场用了多少 token、大约花了多少钱。
/// 点一下展开明细，长按隐藏；位置拖过之后就记住。
struct UsageBall: View {
    let model: SessionModel

    @AppStorage("xidai.ball.hidden") private var hidden = false
    @AppStorage("xidai.ball.x") private var savedX: Double = 0
    @AppStorage("xidai.ball.y") private var savedY: Double = 0

    @State private var drag: CGSize = .zero
    @State private var expanded = false

    private let diameter: CGFloat = 56
    private let inset: CGFloat = 34

    private var input: Int { model.tokens.input }
    private var output: Int { model.tokens.output }
    private var cache: Int { model.tokens.cacheRead }
    private var total: Int { input + output }

    private var cost: Double {
        let fresh = max(0, input - cache)
        return Double(fresh) / 1_000_000 * 3
            + Double(cache) / 1_000_000 * 0.025
            + Double(output) / 1_000_000 * 6
    }

    var body: some View {
        GeometryReader { proxy in
            if !hidden {
                ZStack(alignment: .topLeading) {
                    if expanded {
                        panel
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.trailing, 12)
                            .padding(.top, 210)
                    }
                    bubble
                        .position(x: clamp(x(proxy), lo: inset, hi: proxy.size.width - inset),
                                  y: clamp(y(proxy), lo: 96, hi: proxy.size.height - 40))
                        .gesture(
                            DragGesture(minimumDistance: 3)
                                .onChanged { value in drag = value.translation }
                                .onEnded { value in
                                    savedX = Double(clamp(x(proxy) + value.translation.width,
                                                          lo: inset, hi: proxy.size.width - inset))
                                    savedY = Double(clamp(y(proxy) + value.translation.height,
                                                          lo: 96, hi: proxy.size.height - 40))
                                    drag = .zero
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

    private func x(_ proxy: GeometryProxy) -> CGFloat {
        let base = savedX <= 0 ? proxy.size.width - inset : CGFloat(savedX)
        return base + drag.width
    }

    private func y(_ proxy: GeometryProxy) -> CGFloat {
        let base = savedY <= 0 ? 150 : CGFloat(savedY)
        return base + drag.height
    }

    private func clamp(_ value: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        min(max(value, lo), max(lo, hi))
    }

    private var bubble: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(Palette.stroke, lineWidth: 1)
            VStack(spacing: 0) {
                Text(short(total))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text("token")
                    .font(.system(size: 7.5))
            }
            .foregroundStyle(Palette.secondary)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
        .contentShape(Circle())
        .accessibilityLabel("用量 \(short(total)) token")
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
            line("输入", short(input))
            line("其中缓存", short(cache))
            line("输出", short(output))
            if let context = model.contextTokens {
                line("上下文", short(context))
            }
            Rectangle().fill(Palette.stroke).frame(height: 1).padding(.vertical, 2)
            HStack(spacing: 4) {
                Text("约").foregroundStyle(Palette.secondary)
                Text(money(cost)).foregroundStyle(Palette.ink)
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(11)
        .frame(width: 152, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Palette.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.secondary)
            Spacer(minLength: 6)
            Text(value).foregroundStyle(Palette.ink)
        }
        .font(.system(size: 10.5))
    }

    private func short(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1000 { return String(format: "%.1fk", Double(value) / 1000) }
        return "\(value)"
    }

    private func money(_ value: Double) -> String {
        if value < 0.01 { return "不到 ¥0.01" }
        return String(format: "¥%.2f", value)
    }
}
