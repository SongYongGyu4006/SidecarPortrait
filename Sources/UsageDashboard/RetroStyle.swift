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
            RetroLocalPanel(t: t, m: m).frame(height: 220)
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
                Text("> 한도: 계정 기준(모든 기기 합산)   > 토큰: 이 Mac 기록")
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
                            RetroGaugeRow(gauge: g, tag: gaugeTag(g.label, index: i), color: color, t: t, large: gauges.count <= 2)
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
            Text("> " + (gauge.reset ?? "초기화 시각 정보 없음"))
                .font(monoFont(15)).foregroundStyle(t.dim)
        }
    }
}

/// 이 Mac의 최근 24시간 토큰을 칸 히트맵으로, 오늘·7일 합계를 숫자로
struct RetroLocalPanel: View {
    let t: RetroTheme
    let m: DashboardModel

    var body: some View {
        RetroPanel(t: t, color: t.phosphor) {
            HStack(alignment: .center) {
                PixelText("LOCAL TOKENS", px: 4, color: t.phosphor, glow: t.glow)
                Text("  이 Mac 기록 · 최근 24시간").font(monoFont(14)).foregroundStyle(t.dim)
                Spacer()
                HStack(spacing: 0) {
                    Text("TODAY").frame(width: 150, alignment: .trailing)
                    Text("7 DAYS").frame(width: 150, alignment: .trailing)
                }
                .font(monoFont(14, .semibold)).foregroundStyle(t.dim)
            }
            .padding(.bottom, 22)
            VStack(spacing: 16) {
                row("CLAUDE", m.localClaude, t.claude)
                row("GEMINI", m.localGemini, t.gemini)
                HStack(spacing: 0) {
                    Color.clear.frame(width: 130)
                    ForEach(Array(m.localClaude.hourly.enumerated()), id: \.offset) { i, item in
                        Text(i % 6 == 0 ? hourText(item.hour) : "")
                            .font(monoFont(12)).foregroundStyle(t.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(width: 300)
                }
            }
        }
    }

    func row(_ name: String, _ s: ServiceSummary, _ color: Color) -> some View {
        let peak = max(1, s.hourly.map(\.tokens).max() ?? 1)
        return HStack(spacing: 0) {
            PixelText(name, px: 3.5, color: color, glow: false).frame(width: 130, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(Array(s.hourly.enumerated()), id: \.offset) { _, item in
                    let level = item.tokens == 0 ? 0 : max(0.25, Double(item.tokens) / Double(peak))
                    Rectangle()
                        .fill(level == 0 ? color.opacity(0.08) : color.opacity(level))
                        .shadow(color: t.glow && level > 0.6 ? color.opacity(0.5) : .clear, radius: 4)
                }
            }
            .frame(height: 34)
            HStack(spacing: 0) {
                PixelText(compact(s.today.total), px: 4, color: color, glow: t.glow).frame(width: 150, alignment: .trailing)
                PixelText(compact(s.week.total), px: 4, color: color.opacity(0.6), glow: false).frame(width: 150, alignment: .trailing)
            }
            .frame(width: 300)
        }
    }
}
