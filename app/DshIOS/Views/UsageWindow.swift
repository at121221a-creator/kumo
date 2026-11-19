import SwiftUI

/// 用量悬浮球：像辅助触控那样浮在对话页上，能拖到屏幕任何位置。
/// 点一下展开用量面板，再点收起；面板上 ✕ 把整颗球收掉（设置里能再打开）。
struct UsageWindow: View {
    let model: SessionModel

    @AppStorage("xidai.usage.hidden") private var hidden = false
    @AppStorage("xidai.usage.x") private var savedX: Double = 0
    @AppStorage("xidai.usage.y") private var savedY: Double = 0
    @AppStorage("xidai.usage.open") private var open = false

    @GestureState private var drag: CGSize = .zero

    private let ball: CGFloat = 38
    private let margin: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            if !hidden {
                ZStack(alignment: .topLeading) {
                    if open {
                        panel(proxy)
                            .position(panelPoint(proxy))
                            .gesture(dragGesture(proxy))
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
                    }
                    handle(proxy)
                        .position(ballPoint(proxy))
                        .gesture(dragGesture(proxy))
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) { open.toggle() }
                        }
                        .onLongPressGesture(minimumDuration: 0.7) {
                            withAnimation(.snappy(duration: 0.2)) { hidden = true; open = false }
                        }
                }
            }
        }
    }

    // MARK: 位置

    private func ballPoint(_ proxy: GeometryProxy) -> CGPoint {
        let x = savedX <= 0 ? proxy.size.width - 40 : CGFloat(savedX)
        let y = savedY <= 0 ? proxy.size.height - 160 : CGFloat(savedY)
        return CGPoint(
            x: clamp(x + drag.width, lo: ball / 2 + 6, hi: proxy.size.width - ball / 2 - 6),
            y: clamp(y + drag.height, lo: 70, hi: proxy.size.height - ball / 2 - 8)
        )
    }

    /// 面板贴在球旁边：上方放得下就放上方，否则放下方；左右也不出屏。
    private func panelPoint(_ proxy: GeometryProxy) -> CGPoint {
        let anchor = ballPoint(proxy)
        let width: CGFloat = 152
        let height: CGFloat = 132
        let x = clamp(anchor.x, lo: width / 2 + 8, hi: proxy.size.width - width / 2 - 8)
        let above = anchor.y - height / 2 - ball
        let y = above > 80 ? above : min(anchor.y + height / 2 + ball, proxy.size.height - height / 2 - 8)
        return CGPoint(x: x, y: y)
    }

    private func dragGesture(_ proxy: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let start = CGPoint(
                    x: savedX <= 0 ? proxy.size.width - 40 : CGFloat(savedX),
                    y: savedY <= 0 ? proxy.size.height - 160 : CGFloat(savedY)
                )
                savedX = Double(clamp(start.x + value.translation.width, lo: ball / 2 + 6, hi: proxy.size.width - ball / 2 - 6))
                savedY = Double(clamp(start.y + value.translation.height, lo: 70, hi: proxy.size.height - ball / 2 - 8))
            }
    }

    private func clamp(_ value: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        min(max(value, lo), max(lo, hi))
    }

    // MARK: 球与面板

    private func handle(_ proxy: GeometryProxy) -> some View {
        ZStack {
            Circle()
                .fill(Palette.background.opacity(open ? 0.9 : 0.55))
                .overlay(Circle().strokeBorder(Palette.stroke.opacity(0.9), lineWidth: 1))
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.secondary.opacity(open ? 1 : 0.75))
        }
        .frame(width: ball, height: ball)
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        .contentShape(Circle())
        .accessibilityLabel("本场用量")
    }

    private func panel(_ proxy: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("本场用量")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 6)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { open = false }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { hidden = true; open = false }
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
        .frame(width: 152, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.background.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
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
