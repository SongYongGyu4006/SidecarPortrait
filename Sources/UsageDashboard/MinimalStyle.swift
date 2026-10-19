// 미니멀: 넓은 여백, 가는 글꼴의 큰 숫자, 얇은 선
import SwiftUI

struct MinimalTheme {
    let background: Color
    let text: Color
    let line: Color
    let claude: Color
    let gemini: Color
    let danger: Color
    var secondary: Color { text.opacity(0.5) }

    static func of(_ scheme: ColorScheme) -> MinimalTheme {
        scheme == .dark
            ? MinimalTheme(background: .black, text: .white, line: .white.opacity(0.12),
                           claude: Color(red: 0.91, green: 0.51, blue: 0.36), gemini: Color(red: 0.42, green: 0.61, blue: 1.0),
                           danger: Color(red: 1.0, green: 0.38, blue: 0.35))
            : MinimalTheme(background: Color(red: 0.965, green: 0.963, blue: 0.95), text: Color(red: 0.07, green: 0.07, blue: 0.07),
                           line: .black.opacity(0.1),
                           claude: Color(red: 0.78, green: 0.39, blue: 0.25), gemini: Color(red: 0.18, green: 0.44, blue: 0.88),
                           danger: Color(red: 0.85, green: 0.2, blue: 0.18))
    }
}

struct MinimalDashboard: View {
    let m: DashboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = MinimalTheme.of(scheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI 사용량").font(.system(size: 30, weight: .semibold))
                    Text(dateText(m.now)).font(.system(size: 16)).foregroundStyle(t.secondary)
                }
                Spacer()
                Text(clockText(m.now)).font(.system(size: 72, weight: .thin)).monospacedDigit()
            }
            Rectangle().fill(t.line).frame(height: 1).padding(.vertical, 32)
            HStack(alignment: .top, spacing: 0) {
                column(.claude, t.claude, t)
                Rectangle().fill(t.line).frame(width: 1).padding(.horizontal, 48)
                column(.gemini, t.gemini, t)
            }
            .frame(maxHeight: .infinity)
            Rectangle().fill(t.line).frame(height: 1).padding(.vertical, 24)
            HistoryGrid(m: m, claude: t.claude, gemini: t.gemini,
                        look: TrendLook(grid: t.line, label: t.secondary, danger: t.danger, lineWidth: 1.8, fill: 0.08))
                .frame(height: 250)
        }
        .padding(.horizontal, 56).padding(.vertical, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(t.text)
        .background(t.background)
    }

    func column(_ service: AccountService, _ color: Color, _ t: MinimalTheme) -> some View {
        let state = m.state(service)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(service.title).font(.system(size: 22, weight: .medium))
                Spacer()
                Text(state.statusText(now: m.now)).font(.system(size: 14)).foregroundStyle(t.secondary)
            }
            .padding(.bottom, 28)
            if let notice = state.notice(service) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(notice.title).font(.system(size: 26, weight: .light))
                    Text(notice.detail).font(.system(size: 15)).foregroundStyle(t.secondary)
                }
                .padding(.top, 60)
                Spacer()
            } else {
                ForEach(state.gauges) { g in
                    gauge(g, color, t).frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func gauge(_ g: LimitGauge, _ color: Color, _ t: MinimalTheme) -> some View {
        let tint = g.percent >= 80 ? t.danger : color
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(g.percent)").font(.system(size: 104, weight: .ultraLight)).monospacedDigit()
                    Text("%").font(.system(size: 34, weight: .light)).foregroundStyle(t.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(g.label).font(.system(size: 18, weight: .medium))
                    Text(resetLine(g, now: m.now)).font(.system(size: 14)).foregroundStyle(t.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(t.line)
                    Rectangle().fill(tint).frame(width: geo.size.width * CGFloat(g.percent) / 100)
                }
            }
            .frame(height: 3)
        }
    }
}
