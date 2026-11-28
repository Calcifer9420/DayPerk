import SwiftUI

/// 仅溢出时循环滚动；隐私模式传入圆点，不在视图中保留原金额。
struct OverflowAmount: View {
    let text: String
    var size: CGFloat
    var weight: NSFont.Weight = .semibold
    var alignment: Alignment = .leading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var hovering = false
    @State private var manualOffset = 0.0

    static func width(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)]).width) + 2
    }

    private var label: some View {
        Text(text).font(.system(size: size, weight: weight == .medium ? .medium : .semibold)).monospacedDigit().fixedSize()
    }

    var body: some View {
        GeometryReader { geometry in
            let length = Self.width(text, size: size, weight: weight)
            if length <= geometry.size.width {
                label.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            } else if reduceMotion {
                ScrollView(.horizontal) { label }.scrollIndicators(.hidden)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let offset = hovering ? manualOffset : MarqueeOffset.value(textWidth: length, elapsed: context.date.timeIntervalSince(started))
                    HStack(spacing: 32) { label; label }.offset(x: -offset)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                }.overlay {
                    AmountScrollInput { delta in
                        manualOffset = MarqueeOffset.scrolled(manualOffset, delta: delta, textWidth: length, viewport: geometry.size.width)
                    }
                }.onHover { inside in
                    if inside {
                        manualOffset = min(max(0, length - geometry.size.width), MarqueeOffset.value(textWidth: length, elapsed: Date().timeIntervalSince(started)))
                    } else {
                        // 从手动停留的位置继续，不跳回金额开头。
                        started = Date().addingTimeInterval(-1.2 - manualOffset / 28)
                    }
                    hovering = inside
                }.mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.045),
                                             .init(color: .black, location: 0.955), .init(color: .clear, location: 1)],
                                      startPoint: .leading, endPoint: .trailing))
            }
        }.frame(height: ceil(size * 1.3)).clipped()
            .accessibilityElement(children: .ignore).accessibilityLabel(Text(text)).help(Text(text))
            .onChange(of: text) { old, new in
                if old == "•••" || new == "•••" { started = Date(); manualOffset = 0 }
            }
    }
}

enum MarqueeOffset {
    static func scrolled(_ offset: Double, delta: Double, textWidth: Double, viewport: Double) -> Double {
        guard delta.isFinite else { return offset }
        return min(max(0, textWidth - viewport), max(0, offset - delta))
    }
    static func value(textWidth: Double, elapsed: Double) -> Double {
        guard textWidth.isFinite, textWidth > 0, elapsed.isFinite else { return 0 }
        return (max(0, elapsed - 1.2) * 28).truncatingRemainder(dividingBy: textWidth + 32)
    }
}

private struct AmountScrollInput: NSViewRepresentable {
    var scroll: (Double) -> Void
    func makeNSView(context: Context) -> WheelView { WheelView() }
    func updateNSView(_ view: WheelView, context: Context) { view.scroll = scroll }
    final class WheelView: NSView {
        var scroll: ((Double) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { super.scrollWheel(with: event); return }
            scroll?(event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 10))
        }
        override func mouseDragged(with event: NSEvent) { scroll?(event.deltaX) }
    }
}

/// 面板内的纸屑和彩带：两侧短促喷出，顶部错峰落下，空气阻力减缓落速。
/// 自行绘制矢量纸片，不使用图片、第三方素材或系统外的粒子窗口。
enum ClockOutConfetti {
    static let duration = 5.8
    private static let colors: [Color] = [
        Color(red: 1, green: 0.76, blue: 0.23), Color(red: 1, green: 0.34, blue: 0.49),
        Color(red: 0.25, green: 0.82, blue: 0.94), Color(red: 0.58, green: 0.44, blue: 0.96),
        Color(red: 0.35, green: 0.86, blue: 0.63), Color(red: 1, green: 0.91, blue: 0.61)
    ]

    private static func random(_ index: Int, _ salt: Int) -> Double {
        var value = UInt64(index + 1) &* 0x9E3779B97F4A7C15 &+ UInt64(salt + 1) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return Double((value ^ (value >> 31)) >> 11) / Double(UInt64(1) << 53)
    }

    static func draw(in context: GraphicsContext, size: CGSize, elapsed: Double) {
        guard elapsed >= 0, elapsed < duration, size.width > 0, size.height > 0 else { return }
        for index in 0 ..< 138 {
            let fromTop = index >= 80
            let ribbon = fromTop ? index.isMultiple(of: 2) : index.isMultiple(of: 5)
            let delay = fromTop ? 0.12 + random(index, 0) * 1.1 : random(index, 0) * 0.35
            let age = elapsed - delay
            guard age >= 0 else { continue }
            let phase = random(index, 1) * .pi * 2
            let left = index.isMultiple(of: 2)
            let originX = fromTop ? size.width * (0.04 + random(index, 2) * 0.92) : (left ? -8 : size.width + 8)
            let originY = fromTop ? -60 - random(index, 3) * 40 : size.height * (0.57 + random(index, 3) * 0.12)
            let velocityX = fromTop ? -20 + random(index, 4) * 40 : (left ? 1.0 : -1.0) * (160 + random(index, 4) * 210)
            let velocityY = fromTop ? 25 + random(index, 5) * 50 : -250 - random(index, 5) * 200
            let drag = fromTop ? 0.9 : 1.15
            let terminal = ribbon ? 125 + random(index, 6) * 50 : 175 + random(index, 6) * 70
            let flight = (1 - exp(-drag * age)) / drag
            let sway = (sin(age * (2 + random(index, 7) * 2) + phase) - sin(phase)) * (ribbon ? 16 : 10)
            let position = CGPoint(x: originX + velocityX * flight + sway,
                                   y: originY + terminal * age + (velocityY - terminal) * flight)
            guard position.y < size.height + 100 else { continue }
            var particle = context
            particle.opacity = min(1, max(0, (duration - elapsed) / 0.65))
            particle.translateBy(x: position.x, y: position.y)
            particle.rotate(by: .radians(phase + age * (ribbon ? 0.7 : 2.1) * (left ? 1 : -1)))
            // 翻转时看到纸边，正反面明暗交替，避免所有纸片像平面的发光方块。
            let flip = cos(phase + age * (ribbon ? 2.2 : 5.0))
            particle.scaleBy(x: max(0.16, abs(flip)), y: 1)
            let color = colors[Int(random(index, 8) * Double(colors.count)) % colors.count]
            if ribbon {
                drawRibbon(in: particle, color: color, length: 40 + random(index, 9) * 34,
                           width: 3.5 + random(index, 10) * 2, phase: phase + age * 2)
            } else {
                let width = 6 + random(index, 9) * 5, height = 9 + random(index, 10) * 7
                var paper = Path()
                paper.move(to: CGPoint(x: -width / 2, y: -height / 2))
                paper.addQuadCurve(to: CGPoint(x: width / 2, y: -height / 2 + 1), control: CGPoint(x: 0, y: -height / 2 - 1.5))
                paper.addLine(to: CGPoint(x: width / 2 - 1, y: height / 2))
                paper.addQuadCurve(to: CGPoint(x: -width / 2, y: height / 2 - 1), control: CGPoint(x: 0, y: height / 2 + 1.5))
                paper.closeSubpath()
                particle.fill(paper, with: .linearGradient(Gradient(colors: [color.opacity(0.7), color, .white.opacity(0.85), color]),
                    startPoint: CGPoint(x: -width, y: -height), endPoint: CGPoint(x: width, y: height)))
                particle.stroke(paper, with: .color(color.opacity(flip > 0 ? 0.55 : 0.9)), lineWidth: 0.35)
            }
        }
    }

    private static func drawRibbon(in context: GraphicsContext, color: Color, length: Double, width: Double, phase: Double) {
        // 连续曲线构成卷曲彩带；分段明暗表现转折，不用散点拼接。
        let count = 12
        let amplitude = 4.5
        func center(_ y: Double) -> Double { sin(y / length * .pi * 2.3 + phase) * amplitude }
        for segment in 0 ..< count {
            let y0 = -length / 2 + length * Double(segment) / Double(count)
            let y1 = -length / 2 + length * Double(segment + 1) / Double(count)
            let middle = (y0 + y1) / 2
            let fold = cos(middle / length * .pi * 2.3 + phase)
            func half(_ y: Double) -> Double { width / 2 * (0.35 + abs(cos(y / length * .pi * 2.3 + phase)) * 0.65) }
            var strip = Path()
            strip.move(to: CGPoint(x: center(y0) - half(y0), y: y0))
            strip.addQuadCurve(to: CGPoint(x: center(y1) - half(y1), y: y1), control: CGPoint(x: center(middle) - half(middle), y: middle))
            strip.addLine(to: CGPoint(x: center(y1) + half(y1), y: y1))
            strip.addQuadCurve(to: CGPoint(x: center(y0) + half(y0), y: y0), control: CGPoint(x: center(middle) + half(middle), y: middle))
            strip.closeSubpath()
            let shades = fold > 0 ? [color, color.opacity(0.8), Color.white.opacity(0.9)] : [color.opacity(0.55), color, color.opacity(0.65)]
            context.fill(strip, with: .linearGradient(Gradient(colors: shades), startPoint: CGPoint(x: -6, y: middle), endPoint: CGPoint(x: 6, y: middle)))
        }
    }
}

struct ClockOutCelebrationState {
    let started: Date
    let menuAmountWasVisible: Bool
    var endsAt: Date { started.addingTimeInterval(ClockOutConfetti.duration) }
    func retainsMenuAmount(at date: Date) -> Bool { menuAmountWasVisible && date >= started && date < endsAt }
}

/// 播放生命周期由共享的下班状态管理，菜单栏和礼花同时结束。
struct ClockOutCelebration: View {
    let started: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if reduceMotion {
                Text(L10n.text("celebration.emoji")).font(.system(size: 44)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                    Canvas(rendersAsynchronously: true) { graphics, bounds in
                        ClockOutConfetti.draw(in: graphics, size: bounds, elapsed: max(0, context.date.timeIntervalSince(started)))
                    }
                }
            }
        }.clipped()
    }
}
