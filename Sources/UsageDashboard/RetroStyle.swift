// 레트로 픽셀: 도트 글꼴과 칸 막대, CRT(다크) 또는 LCD(라이트) 화면
import SwiftUI

struct RetroDashboard: View {
    let m: DashboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = RetroTheme.of(scheme)
        VStack(spacing: 22) {
            header(t)
            HStack(spacing: 22) {
                RetroAccountPanel(service: .claude, color: t.claude, t: t, m: m)
                RetroAccountPanel(service: .gemini, color: t.gemini, t: t, m: m)
            }
            RetroHistoryPanel(t: t, m: m).frame(height: 310)
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.background)
        .overlay(Scanlines(opacity: t.scanline))
    }

    func header(_ t: RetroTheme) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    PixelText("AI USAGE", px: 7, color: t.phosphor, glow: t.glow)
                    Rectangle().fill(t.phosphor).frame(width: 22, height: 42)
                        .opacity(m.blink ? 1 : 0)
                        .shadow(color: t.glow ? t.phosphor.opacity(0.7) : .clear, radius: 8)
                }
                Text("> 계정 기준 · 모든 기기 합산")
                    .font(monoFont(15)).foregroundStyle(t.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 12) {
                PixelText(clockText(m.now, colon: m.blink), px: 10, color: t.phosphor, glow: t.glow)
                Text(m.now.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(monoFont(15)).foregroundStyle(t.dim)
            }
        }
    }
}

struct RetroAccountPanel: View {
    let service: AccountService
    let color: Color
    let t: RetroTheme
    let m: DashboardModel

    var body: some View {
        let state = m.state(service)
        RetroPanel(t: t, color: color) {
            HStack(alignment: .center) {
                PixelText(service.title, px: 6, color: color, glow: t.glow)
                Spacer()
                Text("[ \(state.statusText(now: m.now)) ]").font(monoFont(15, .semibold))
                    .foregroundStyle(state.notice(service) == nil || state == .loading ? t.dim : t.danger)
            }
            Rectangle().fill(color.opacity(0.25)).frame(height: 2).padding(.vertical, 20)
            Group {
                if let notice = state.notice(service) {
                    VStack(alignment: .leading, spacing: 18) {
                        PixelText(state == .loading ? "LOADING" : "CHECK!", px: 8, color: state == .loading ? color : t.danger, glow: t.glow)
                        Text("> \(notice.title)\n> \(notice.detail)\(m.blink ? "_" : " ")")
                            .font(monoFont(16)).foregroundStyle(t.dim)
                    }
                    .padding(.top, 40)
                } else {
                    // 한도 수만큼 패널 높이를 고르게 나눠 쓴다
                    let gauges = state.gauges
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(gauges.enumerated()), id: \.element.id) { i, g in
                            RetroGaugeRow(gauge: g, tag: gaugeTag(g.label, index: i), color: color, t: t, large: gauges.count <= 2, now: m.now)
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct RetroGaugeRow: View {
    let gauge: LimitGauge
    let tag: String
    let color: Color
    let t: RetroTheme
    let large: Bool
    let now: Date

    var body: some View {
        let tint = gauge.percent >= 80 ? t.danger : color
        VStack(alignment: .leading, spacing: large ? 18 : 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    PixelText(tag, px: 3.5, color: t.dim, glow: false)
                    Text(gauge.label).font(monoFont(14)).foregroundStyle(t.dim)
                }
                Spacer()
                PixelText("\(gauge.percent)%", px: large ? 12 : 8, color: tint, glow: t.glow)
            }
            SegmentBar(fraction: Double(gauge.percent) / 100, cells: 25, color: tint, glow: t.glow)
                .frame(height: large ? 40 : 28)
            Text("> " + resetLine(gauge, now: now))
                .font(monoFont(15)).foregroundStyle(t.dim)
        }
    }
}

/// 계정 사용률 추이: 서비스마다 현재(24시간)·주간(7일)
struct RetroHistoryPanel: View {
    let t: RetroTheme
    let m: DashboardModel

    var body: some View {
        RetroPanel(t: t, color: t.phosphor) {
            HStack(alignment: .center) {
                PixelText("HISTORY", px: 4, color: t.phosphor, glow: t.glow)
                Text("  계정 사용률 추이 · ↺ 초기화").font(monoFont(14)).foregroundStyle(t.dim)
            }
            .padding(.bottom, 14)
            HistoryGrid(m: m, claude: t.claude, gemini: t.gemini,
                        look: TrendLook(grid: t.phosphor.opacity(0.18), label: t.dim, danger: t.danger,
                                        font: { monoFont($0, $1) }, lineWidth: 3, glow: t.glow ? 4 : 0, fill: 0.18, square: true),
                        serviceLabel: { s, c in AnyView(PixelText(s.title, px: 2.5, color: c, glow: false)) })
        }
    }
}
