// 네온 사이버펑크: 원근 격자 배경, 빛나는 원형 게이지
import SwiftUI

struct NeonTheme {
    let top: Color
    let bottom: Color
    let grid: Color
    let panel: Color
    let text: Color
    let claude: Color
    let gemini: Color
    let danger: Color
    let glow: CGFloat
    var secondary: Color { text.opacity(0.6) }

    static func of(_ scheme: ColorScheme) -> NeonTheme {
        scheme == .dark
            ? NeonTheme(top: Color(red: 0.04, green: 0.01, blue: 0.10), bottom: Color(red: 0.16, green: 0.02, blue: 0.22),
                        grid: Color(red: 0.75, green: 0.2, blue: 1.0).opacity(0.35), panel: Color.black.opacity(0.45),
                        text: .white, claude: Color(red: 1.0, green: 0.24, blue: 0.65), gemini: Color(red: 0.0, green: 0.9, blue: 1.0),
                        danger: Color(red: 1.0, green: 0.88, blue: 0.3), glow: 14)
            : NeonTheme(top: Color(red: 0.99, green: 0.95, blue: 1.0), bottom: Color(red: 0.88, green: 0.84, blue: 1.0),
                        grid: Color(red: 0.55, green: 0.17, blue: 0.89).opacity(0.22), panel: Color.white.opacity(0.65),
                        text: Color(red: 0.10, green: 0.04, blue: 0.24), claude: Color(red: 0.88, green: 0.0, blue: 0.48),
                        gemini: Color(red: 0.0, green: 0.55, blue: 0.70), danger: Color(red: 0.85, green: 0.35, blue: 0.0), glow: 5)
    }
}

/// 지평선으로 모이는 원근 격자
struct NeonGrid: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let horizon = size.height * 0.55
            let cx = size.width / 2
            var lines = Path()
            for k in -14...14 {
                let x = cx + CGFloat(k) * size.width / 9
                lines.move(to: CGPoint(x: cx + CGFloat(k) * 30, y: horizon))
                lines.addLine(to: CGPoint(x: x, y: size.height))
            }
            var depth: CGFloat = 6
            while horizon + depth < size.height {
                lines.move(to: CGPoint(x: 0, y: horizon + depth))
                lines.addLine(to: CGPoint(x: size.width, y: horizon + depth))
                depth *= 1.32
            }
            ctx.stroke(lines, with: .color(color), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

struct NeonDashboard: View {
    let m: DashboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = NeonTheme.of(scheme)
        VStack(spacing: 24) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI USAGE").font(.system(size: 52, weight: .black, design: .rounded)).italic()
                        .foregroundStyle(LinearGradient(colors: [t.claude, t.gemini], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: t.claude.opacity(0.7), radius: t.glow)
                    Text("ACCOUNT LIMITS · ALL DEVICES").font(.system(size: 14, weight: .semibold, design: .rounded))
                        .tracking(4).foregroundStyle(t.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(clockText(m.now)).font(.system(size: 60, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(t.gemini).shadow(color: t.gemini.opacity(0.8), radius: t.glow)
                    Text(dateText(m.now)).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(t.secondary)
                }
            }
            HStack(spacing: 24) {
                panel(.claude, t.claude, t)
                panel(.gemini, t.gemini, t)
            }
            neonBox(t.grid.opacity(1), t) {
                HistoryGrid(m: m, claude: t.claude, gemini: t.gemini,
                            look: TrendLook(grid: t.grid, label: t.secondary, danger: t.danger,
                                            font: { .system(size: $0, weight: $1, design: .rounded) }, lineWidth: 3, glow: t.glow / 2, fill: 0.2),
                            serviceLabel: { s, c in
                                AnyView(Text(s.title.uppercased()).font(.system(size: 15, weight: .black, design: .rounded)).italic()
                                    .foregroundStyle(c).shadow(color: c.opacity(0.8), radius: t.glow / 3))
                            })
            }
            .frame(height: 290)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(t.text)
        .background(
            ZStack {
                LinearGradient(colors: [t.top, t.bottom], startPoint: .top, endPoint: .bottom)
                NeonGrid(color: t.grid)
            }
        )
    }

    func neonBox<C: View>(_ color: Color, _ t: NeonTheme, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(t.panel))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(LinearGradient(colors: [color, color.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                    .shadow(color: color.opacity(0.8), radius: t.glow)
            )
    }

    func panel(_ service: AccountService, _ color: Color, _ t: NeonTheme) -> some View {
        let state = m.state(service)
        return neonBox(color, t) {
            VStack(spacing: 0) {
                HStack {
                    Text(service.title.uppercased()).font(.system(size: 34, weight: .black, design: .rounded)).italic()
                        .foregroundStyle(color).shadow(color: color.opacity(0.8), radius: t.glow)
                    Spacer()
                    Text(state.statusText(now: m.now)).font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(t.secondary)
                }
                if let notice = state.notice(service) {
                    Spacer()
                    Text(notice.title).font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(color).shadow(color: color, radius: t.glow / 2)
                    Text(notice.detail).font(.system(size: 15, design: .rounded)).foregroundStyle(t.secondary).padding(.top, 8)
                    Spacer()
                } else {
                    HStack(spacing: 20) {
                        ForEach(Array(state.gauges.enumerated()), id: \.element.id) { i, g in
                            NeonRing(gauge: g, tag: gaugeTag(g.label, index: i), color: g.percent >= 80 ? t.danger : color, t: t, now: m.now,
                                     size: state.gauges.count > 2 ? 150 : 210)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

struct NeonRing: View {
    let gauge: LimitGauge
    let tag: String
    let color: Color
    let t: NeonTheme
    let now: Date
    let size: CGFloat

    var body: some View {
        let line = size * 0.1
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: line)
                Circle().trim(from: 0, to: max(0.004, Double(gauge.percent) / 100))
                    .stroke(AngularGradient(colors: [color.opacity(0.5), color], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * Double(max(1, gauge.percent)) / 100)),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.9), radius: t.glow)
                VStack(spacing: 2) {
                    Text("\(gauge.percent)%").font(.system(size: size * 0.24, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(color).shadow(color: color.opacity(0.8), radius: t.glow / 2)
                    Text(tag).font(.system(size: 14, weight: .black, design: .rounded)).tracking(3).foregroundStyle(t.secondary)
                }
            }
            .frame(width: size, height: size)
            VStack(spacing: 4) {
                Text(gauge.label).font(.system(size: 16, weight: .bold, design: .rounded))
                Text(resetLine(gauge, now: now)).font(.system(size: 13, design: .rounded)).foregroundStyle(t.secondary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
    }
}
