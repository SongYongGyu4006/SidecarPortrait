// 자동차 계기판: 바늘이 도는 원형 계기와 주행 거리계 같은 토큰 숫자
import SwiftUI

struct GaugeTheme {
    let background: [Color]
    let face: Color
    let bezel: [Color]
    let tick: Color
    let text: Color
    let needle: Color
    let claude: Color
    let gemini: Color
    let redZone: Color
    let lcd: Color
    let lcdText: Color
    var secondary: Color { text.opacity(0.55) }

    static func of(_ scheme: ColorScheme) -> GaugeTheme {
        scheme == .dark
            ? GaugeTheme(background: [Color(red: 0.11, green: 0.12, blue: 0.13), Color(red: 0.03, green: 0.03, blue: 0.04)],
                         face: Color(red: 0.07, green: 0.075, blue: 0.085),
                         bezel: [Color(red: 0.55, green: 0.57, blue: 0.6), Color(red: 0.18, green: 0.19, blue: 0.21)],
                         tick: .white.opacity(0.85), text: .white, needle: Color(red: 1.0, green: 0.23, blue: 0.19),
                         claude: Color(red: 1.0, green: 0.62, blue: 0.26), gemini: Color(red: 0.24, green: 0.65, blue: 1.0),
                         redZone: Color(red: 1.0, green: 0.23, blue: 0.19),
                         lcd: Color(red: 0.02, green: 0.06, blue: 0.08), lcdText: Color(red: 0.45, green: 0.85, blue: 1.0))
            : GaugeTheme(background: [Color(red: 0.93, green: 0.91, blue: 0.86), Color(red: 0.84, green: 0.81, blue: 0.75)],
                         face: Color(red: 0.985, green: 0.97, blue: 0.94),
                         bezel: [Color(red: 0.92, green: 0.89, blue: 0.83), Color(red: 0.62, green: 0.58, blue: 0.51)],
                         tick: Color(red: 0.12, green: 0.12, blue: 0.12), text: Color(red: 0.1, green: 0.1, blue: 0.1),
                         needle: Color(red: 0.82, green: 0.0, blue: 0.1),
                         claude: Color(red: 0.85, green: 0.45, blue: 0.11), gemini: Color(red: 0.12, green: 0.44, blue: 0.82),
                         redZone: Color(red: 0.82, green: 0.0, blue: 0.1),
                         lcd: Color(red: 0.74, green: 0.78, blue: 0.68), lcdText: Color(red: 0.1, green: 0.14, blue: 0.1))
    }
}

struct GaugeDashboard: View {
    let m: DashboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = GaugeTheme.of(scheme)
        VStack(spacing: 26) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI USAGE").font(.system(size: 40, weight: .heavy)).italic().tracking(2)
                    Text("계정 한도 · 모든 기기 합산").font(.system(size: 15, weight: .medium)).foregroundStyle(t.secondary)
                }
                Spacer()
                lcd(clockText(m.now, colon: m.blink), sub: dateText(m.now), t: t)
            }
            HStack(spacing: 26) {
                cluster(.claude, t.claude, t)
                cluster(m.secondService, t.gemini, t)
            }
            HistoryGrid(m: m, claude: t.claude, gemini: t.gemini,
                        look: TrendLook(grid: t.tick.opacity(0.15), label: t.secondary, danger: t.redZone,
                                        font: { .system(size: $0, weight: $1, design: .monospaced) }, lineWidth: 2.5, fill: 0.15),
                        serviceLabel: { s, c in
                            AnyView(HStack(spacing: 8) {
                                Capsule().fill(c).frame(width: 18, height: 4)
                                Text(s.title.uppercased()).font(.system(size: 13, weight: .heavy)).italic().tracking(2)
                            })
                        })
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 20).fill(t.face.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(LinearGradient(colors: t.bezel, startPoint: .top, endPoint: .bottom), lineWidth: 2))
                .frame(height: 290)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(t.text)
        .background(RadialGradient(colors: t.background, center: .top, startRadius: 100, endRadius: 1300))
    }

    func lcd(_ text: String, sub: String, t: GaugeTheme) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(text).font(.system(size: 48, weight: .medium, design: .monospaced)).monospacedDigit()
            Text(sub).font(.system(size: 14, weight: .medium, design: .monospaced)).opacity(0.7)
        }
        .foregroundStyle(t.lcdText)
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(t.lcd))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LinearGradient(colors: t.bezel, startPoint: .top, endPoint: .bottom), lineWidth: 3))
    }

    func cluster(_ service: AccountService, _ color: Color, _ t: GaugeTheme) -> some View {
        let state = m.state(service)
        return VStack(spacing: 14) {
            HStack {
                Capsule().fill(color).frame(width: 28, height: 6)
                Text(service.title.uppercased()).font(.system(size: 24, weight: .heavy)).italic().tracking(3)
                Spacer()
                Text(state.statusText(now: m.now)).font(.system(size: 14, weight: .medium)).foregroundStyle(t.secondary)
            }
            if let notice = state.notice(service) {
                VStack(spacing: 10) {
                    Image(systemName: state == .loading ? "gauge.with.dots.needle.33percent" : "exclamationmark.triangle.fill")
                        .font(.system(size: 54)).foregroundStyle(state == .loading ? color : t.redZone)
                    Text(notice.title).font(.system(size: 22, weight: .bold))
                    Text(notice.detail).font(.system(size: 15)).foregroundStyle(t.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 22) {
                    ForEach(Array(state.gauges.enumerated()), id: \.element.id) { i, g in
                        DialGauge(gauge: g, tag: gaugeTag(g.label, index: i), color: color, t: t, now: m.now)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 28).fill(t.face.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(LinearGradient(colors: t.bezel, startPoint: .top, endPoint: .bottom).opacity(0.6), lineWidth: 2))
    }
}

/// 240도로 열린 원형 계기. 80% 위는 빨간 구간.
struct DialGauge: View {
    let gauge: LimitGauge
    let tag: String
    let color: Color
    let t: GaugeTheme
    let now: Date

    var body: some View {
        VStack(spacing: 14) {
            Canvas { ctx, size in draw(ctx, size: size) }
                .aspectRatio(1, contentMode: .fit)
                .background(Circle().fill(t.face))
                .overlay(Circle().stroke(LinearGradient(colors: t.bezel, startPoint: .top, endPoint: .bottom), lineWidth: 9))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            Text(resetLine(gauge, now: now)).font(.system(size: 13, weight: .medium)).foregroundStyle(t.secondary)
                .multilineTextAlignment(.center).lineLimit(2)
        }
    }

    func draw(_ ctx: GraphicsContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = size.width / 2 * 0.86
        let start = 150.0, sweep = 240.0
        func angle(_ p: Double) -> Angle { .degrees(start + sweep * p) }
        func point(_ radius: CGFloat, _ p: Double) -> CGPoint {
            let a = angle(p).radians
            return CGPoint(x: c.x + radius * CGFloat(cos(a)), y: c.y + radius * CGFloat(sin(a)))
        }
        let fraction = Double(gauge.percent) / 100

        // 빨간 구간과 진행 호
        var red = Path()
        red.addArc(center: c, radius: r * 0.93, startAngle: angle(0.8), endAngle: angle(1), clockwise: false)
        ctx.stroke(red, with: .color(t.redZone.opacity(0.85)), lineWidth: r * 0.07)
        var track = Path()
        track.addArc(center: c, radius: r * 0.78, startAngle: angle(0), endAngle: angle(1), clockwise: false)
        ctx.stroke(track, with: .color(t.tick.opacity(0.1)), style: StrokeStyle(lineWidth: r * 0.06, lineCap: .round))
        if fraction > 0 {
            var arc = Path()
            arc.addArc(center: c, radius: r * 0.78, startAngle: angle(0), endAngle: angle(fraction), clockwise: false)
            ctx.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: r * 0.06, lineCap: .round))
        }

        // 눈금과 숫자
        for i in 0...50 {
            let p = Double(i) / 50
            let major = i % 10 == 0
            var tick = Path()
            tick.move(to: point(r * (major ? 0.84 : 0.89), p))
            tick.addLine(to: point(r * 0.97, p))
            ctx.stroke(tick, with: .color(t.tick.opacity(major ? 1 : 0.5)), lineWidth: major ? 3 : 1.2)
            if major {
                ctx.draw(Text("\(i * 2)").font(.system(size: r * 0.12, weight: .semibold)).foregroundColor(t.tick),
                         at: point(r * 0.66, p))
            }
        }

        // 가운데 글자
        ctx.draw(Text(tag).font(.system(size: r * 0.12, weight: .heavy)).foregroundColor(t.text.opacity(0.55)),
                 at: CGPoint(x: c.x, y: c.y - r * 0.32))
        ctx.draw(Text("\(gauge.percent)%").font(.system(size: r * 0.3, weight: .bold, design: .monospaced))
                    .foregroundColor(gauge.percent >= 80 ? t.redZone : t.text),
                 at: CGPoint(x: c.x, y: c.y + r * 0.42))
        ctx.draw(Text(gauge.label).font(.system(size: r * 0.1, weight: .medium)).foregroundColor(t.text.opacity(0.55)),
                 at: CGPoint(x: c.x, y: c.y + r * 0.68))

        // 바늘
        var needle = Path()
        needle.move(to: point(-r * 0.14, fraction))
        needle.addLine(to: point(r * 0.86, fraction))
        ctx.stroke(needle, with: .color(t.needle), style: StrokeStyle(lineWidth: r * 0.035, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.09, y: c.y - r * 0.09, width: r * 0.18, height: r * 0.18)),
                 with: .color(t.needle))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.04, y: c.y - r * 0.04, width: r * 0.08, height: r * 0.08)),
                 with: .color(t.face))
    }
}
