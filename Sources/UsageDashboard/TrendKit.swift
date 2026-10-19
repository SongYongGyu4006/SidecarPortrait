// 계정 사용률 추이 그래프. 모든 스타일이 색과 글꼴만 바꿔 함께 쓴다.
//   - 값은 다음 기록까지 그대로라 계단 모양으로 그린다
//   - 값이 크게 떨어지면 초기화로 보고 선을 끊은 뒤 세로 점선과 ↺ 표시를 남긴다
//   - 20분 넘게 기록이 없으면(대시보드가 꺼져 있었으면) 그 구간은 비워 둔다
import SwiftUI

struct TrendLook {
    var grid: Color
    var label: Color
    var danger: Color
    var font: (CGFloat, Font.Weight) -> Font = { .system(size: $0, weight: $1) }
    var lineWidth: CGFloat = 2.5
    var glow: CGFloat = 0
    var fill: Double = 0.14
    /// 레트로: 둥근 끝 없이 각지게 그린다
    var square = false
}

/// 그래프 한 칸이 보여 줄 범위
enum TrendSpan {
    case day, week

    var seconds: TimeInterval { self == .day ? 24 * 3600 : 7 * 24 * 3600 }
    var title: String { self == .day ? "24시간" : "7일" }
}

struct TrendChart: View {
    let samples: [HistorySample]
    let span: TrendSpan
    let now: Date
    let color: Color
    let look: TrendLook

    /// 이 간격보다 오래 비면 선을 잇지 않는다 (기록 주기 5분)
    static let maxGap: TimeInterval = 20 * 60

    var visible: [HistorySample] {
        let start = now.addingTimeInterval(-span.seconds)
        return samples.filter { $0.t >= start && $0.t <= now }.sorted { $0.t < $1.t }
    }

    var body: some View {
        let points = visible
        Canvas { ctx, size in draw(ctx, size: size, points: points) }
            .overlay {
                if points.count < 2 {
                    Text(points.isEmpty ? "기록 수집 중 · 5분마다 저장돼요" : "기록 수집 중")
                        .font(look.font(13, .medium)).foregroundStyle(look.label)
                        .padding(.trailing, 34).padding(.bottom, 18)
                        .offset(y: -18)  // 50% 눈금선과 겹치지 않게 조금 위로
                }
            }
    }

    func draw(_ ctx: GraphicsContext, size: CGSize, points: [HistorySample]) {
        // 위쪽은 "100" 눈금 글자와 100% 선이 잘리지 않을 만큼 비운다
        let right: CGFloat = 34, bottom: CGFloat = 18, top: CGFloat = 9
        let w = size.width - right, h = size.height - bottom
        let start = now.addingTimeInterval(-span.seconds)
        func x(_ t: Date) -> CGFloat { CGFloat(t.timeIntervalSince(start) / span.seconds) * w }
        func y(_ v: Int) -> CGFloat { h - CGFloat(min(100, max(0, v))) / 100 * (h - top) }
        // 가장자리 글자가 잘리지 않게 안쪽으로 붙인다
        func axisLabel(_ text: String, at px: CGFloat) {
            ctx.draw(Text(text).font(look.font(11, .regular)).foregroundColor(look.label),
                     at: CGPoint(x: min(max(px, 14), w - 14), y: h + 4), anchor: .top)
        }

        // 눈금: 0·50·100% 가로선, 80% 경고선, 시간 눈금
        for v in [0, 50, 100] {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y(v)))
            line.addLine(to: CGPoint(x: w, y: y(v)))
            ctx.stroke(line, with: .color(look.grid), style: StrokeStyle(lineWidth: 1, dash: v == 0 ? [] : [3, 4]))
            ctx.draw(Text("\(v)").font(look.font(11, .regular)).foregroundColor(look.label),
                     at: CGPoint(x: w + 6, y: y(v)), anchor: .leading)
        }
        var warn = Path()
        warn.move(to: CGPoint(x: 0, y: y(80)))
        warn.addLine(to: CGPoint(x: w, y: y(80)))
        ctx.stroke(warn, with: .color(look.danger.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        let cal = Calendar.current
        if span == .day {
            var t = cal.dateInterval(of: .hour, for: start)!.end
            while t < now {
                let hour = cal.component(.hour, from: t)
                if hour % 6 == 0 { axisLabel("\(hour)시", at: x(t)) }
                t = t.addingTimeInterval(3600)
            }
        } else {
            var t = cal.startOfDay(for: start.addingTimeInterval(86400))
            while t < now {
                var tick = Path()
                tick.move(to: CGPoint(x: x(t), y: h))
                tick.addLine(to: CGPoint(x: x(t), y: h + 3))
                ctx.stroke(tick, with: .color(look.grid), lineWidth: 1)
                // 요일은 그날 한가운데에 쓴다. 맨 오른쪽 오늘은 지금까지의 가운데에 "오늘"로 쓴다.
                let today = cal.isDate(t, inSameDayAs: now)
                axisLabel(today ? "오늘" : t.formatted(.dateTime.weekday(.narrow)),
                          at: today ? (x(t) + x(now)) / 2 : x(t.addingTimeInterval(43200)))
                t = t.addingTimeInterval(86400)
            }
        }
        guard !points.isEmpty else { return }

        // 끊김(기록 공백)과 초기화(값 하락)로 구간을 나눈다
        var segments: [[HistorySample]] = [[points[0]]]
        var resets: [Date] = []
        for (prev, p) in zip(points, points.dropFirst()) {
            // 한도는 초기화 때만 줄어든다. 반올림 차이 같은 작은 하락은 초기화로 보지 않는다.
            let reset = p.v <= prev.v - 5 || (prev.v > 0 && p.v == 0)
            if reset { resets.append(p.t) }
            if reset || p.t.timeIntervalSince(prev.t) > Self.maxGap {
                segments.append([p])
            } else {
                segments[segments.count - 1].append(p)
            }
        }

        for t in resets {
            var marker = Path()
            marker.move(to: CGPoint(x: x(t), y: 0))
            marker.addLine(to: CGPoint(x: x(t), y: h))
            ctx.stroke(marker, with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            // 오른쪽 끝이면 눈금 글자와 겹치지 않게 선 왼쪽에 쓴다
            let nearEdge = x(t) > w - 16
            ctx.draw(Text("↺").font(look.font(12, .bold)).foregroundColor(color),
                     at: CGPoint(x: x(t) + (nearEdge ? -3 : 3), y: 2), anchor: nearEdge ? .topTrailing : .topLeading)
        }

        let last = points.last!
        let live = now.timeIntervalSince(last.t) <= Self.maxGap
        var glowCtx = ctx
        if look.glow > 0 { glowCtx.addFilter(.shadow(color: color.opacity(0.8), radius: look.glow)) }
        for (i, seg) in segments.enumerated() {
            var line = Path()
            line.move(to: CGPoint(x: x(seg[0].t), y: y(seg[0].v)))
            for (a, b) in zip(seg, seg.dropFirst()) {
                line.addLine(to: CGPoint(x: x(b.t), y: y(a.v)))
                line.addLine(to: CGPoint(x: x(b.t), y: y(b.v)))
            }
            // 마지막 구간이 지금까지 이어지면 현재 시각까지 늘인다
            let endX = i == segments.count - 1 && live ? x(now) : x(seg.last!.t)
            line.addLine(to: CGPoint(x: max(endX, x(seg.last!.t) + 2), y: y(seg.last!.v)))
            var area = line
            area.addLine(to: CGPoint(x: max(endX, x(seg.last!.t) + 2), y: h))
            area.addLine(to: CGPoint(x: x(seg[0].t), y: h))
            area.closeSubpath()
            ctx.fill(area, with: .color(color.opacity(look.fill)))
            glowCtx.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: look.lineWidth, lineCap: look.square ? .butt : .round,
                                              lineJoin: look.square ? .miter : .round))
        }

        // 지금 값
        let dotColor = last.v >= 80 ? look.danger : color
        let dot = CGPoint(x: live ? x(now) : x(last.t), y: y(last.v))
        let r: CGFloat = look.square ? 4 : 4.5
        let rect = CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)
        glowCtx.fill(look.square ? Path(rect) : Path(ellipseIn: rect), with: .color(dotColor))
    }
}

/// 추이 그래프 한 칸: 제목, 지금 값, 초기화까지 남은 시간, 그래프
struct TrendCell: View {
    let title: String
    let gauge: LimitGauge?
    let samples: [HistorySample]
    let span: TrendSpan
    let now: Date
    let color: Color
    let look: TrendLook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(look.font(13, .semibold)).foregroundStyle(look.label)
                Spacer(minLength: 4)
                if let gauge {
                    Text("\(gauge.percent)%").font(look.font(15, .bold))
                        .foregroundStyle(gauge.percent >= 80 ? look.danger : color)
                }
            }
            Text(countdown).font(look.font(11, .regular)).foregroundStyle(look.label).lineLimit(1)
            TrendChart(samples: samples, span: span, now: now, color: color, look: look)
        }
    }

    var countdown: String {
        guard let gauge else { return "값을 읽는 중" }
        guard let left = countdownText(until: nextResetDate(gauge.reset, now: now), now: now) else { return gauge.reset ?? " " }
        return left == "곧" ? "곧 초기화" : "초기화까지 \(left)"
    }
}

/// 아래 패널 내용: 서비스마다 현재(24시간)·주간(7일) 추이 두 칸
struct HistoryGrid: View {
    let m: DashboardModel
    let claude: Color
    let gemini: Color
    let look: TrendLook
    /// 서비스 이름을 스타일에 맞게 그린다
    var serviceLabel: (AccountService, Color) -> AnyView = { s, c in
        AnyView(Text(s.title).font(.system(size: 14, weight: .bold)).foregroundStyle(c))
    }

    var body: some View {
        HStack(spacing: 28) {
            block(.claude, claude)
            Rectangle().fill(look.grid).frame(width: 1)
            block(.gemini, gemini)
        }
    }

    func block(_ service: AccountService, _ color: Color) -> some View {
        let gauges = m.state(service).gauges
        func gauge(_ tag: String) -> LimitGauge? {
            gauges.enumerated().first { gaugeTag($0.element.label, index: $0.offset) == tag }?.element
        }
        return VStack(alignment: .leading, spacing: 8) {
            serviceLabel(service, color)
            HStack(spacing: 20) {
                TrendCell(title: "현재 · 24시간", gauge: gauge("NOW"), samples: m.history.samples(HistoryKey(service: service, tag: "NOW")),
                          span: .day, now: m.now, color: color, look: look)
                TrendCell(title: "주간 · 7일", gauge: gauge("WEEK"), samples: m.history.samples(HistoryKey(service: service, tag: "WEEK")),
                          span: .week, now: m.now, color: color, look: look)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
