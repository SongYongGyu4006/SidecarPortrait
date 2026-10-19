// 계정 사용률 기록: 사용량 페이지를 읽을 때마다 한도별 %와 시각만 저장해 추이 그래프로 그린다.
// 값이 계정 기준이라 다른 기기에서 쓴 양도 반영된다. 대시보드가 꺼져 있던 동안은 기록이 비어 있다.
import Foundation

struct HistorySample: Codable, Equatable {
    let t: Date
    let v: Int
}

/// 서비스와 한도 종류(NOW·WEEK)로 기록을 나눈다
struct HistoryKey: Hashable {
    let service: AccountService
    let tag: String
    var id: String { "\(service.rawValue).\(tag)" }
}

final class UsageHistory: ObservableObject {
    @Published private(set) var series: [String: [HistorySample]] = [:]
    /// 이보다 오래된 기록은 버린다 (7일 그래프 + 여유)
    private let keep: TimeInterval = 8 * 24 * 3600
    private let url: URL

    /// `USAGE_DASHBOARD_HISTORY` 환경 변수로 다른 파일을 쓸 수 있다 (화면 확인용)
    init() {
        if let custom = ProcessInfo.processInfo.environment["USAGE_DASHBOARD_HISTORY"] {
            url = URL(fileURLWithPath: custom)
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("UsageDashboard", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("history.json")
        }
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder.history.decode([String: [HistorySample]].self, from: data) {
            series = saved
        }
    }

    func samples(_ key: HistoryKey) -> [HistorySample] { series[key.id] ?? [] }

    func record(_ service: AccountService, gauges: [LimitGauge], at date: Date) {
        var changed = false
        var seen = Set<String>()
        for (i, g) in gauges.enumerated() {
            let id = HistoryKey(service: service, tag: gaugeTag(g.label, index: i)).id
            // 같은 종류 한도가 여럿이면(예: 모델별 주간 한도) 첫 번째만 그래프에 기록한다
            guard seen.insert(id).inserted else { continue }
            var list = series[id] ?? []
            // 같은 값을 짧은 간격으로 또 읽었으면 건너뛴다
            if let last = list.last, last.v == g.percent, date.timeIntervalSince(last.t) < 4 * 60 { continue }
            list.append(HistorySample(t: date, v: g.percent))
            series[id] = list.filter { date.timeIntervalSince($0.t) < keep }
            changed = true
        }
        if changed { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder.history.encode(series) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static let history: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let history: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - 초기화 시각

/// "오전 11:20에 재설정", "재설정: (수요일) 오후 10:00", "10월 20일 오후 3:01에 초기화",
/// "Resets in 4 hr 12 min", "Resets Tue 9:00 AM" 같은 문구에서 다음 초기화 시각을 구한다
func nextResetDate(_ text: String?, now: Date) -> Date? {
    guard let text else { return nil }
    let cal = Calendar.current
    func match(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }

    // 상대 시간 ("in 4 hr 12 min", "4시간 12분 후")
    for pattern in [#"\bin\s+(?:(\d+)\s*(?:hr|hrs|hours?|h)\b)?\s*(?:(\d+)\s*(?:min|mins|minutes?|m)\b)?"#,
                    #"(?:(\d+)\s*시간)?\s*(?:(\d+)\s*분)?\s*후"#] {
        if let g = match(pattern), !(g[1].isEmpty && g[2].isEmpty) {
            return now.addingTimeInterval(Double(Int(g[1]) ?? 0) * 3600 + Double(Int(g[2]) ?? 0) * 60)
        }
    }

    // 시각
    var hour: Int?, minute = 0
    if let g = match(#"(오전|오후)\s*(\d{1,2}):(\d{2})"#) {
        hour = (Int(g[2]) ?? 0) % 12 + (g[1] == "오후" ? 12 : 0)
        minute = Int(g[3]) ?? 0
    } else if let g = match(#"(\d{1,2}):(\d{2})\s*(AM|PM)"#) {
        hour = (Int(g[1]) ?? 0) % 12 + (g[3].uppercased() == "PM" ? 12 : 0)
        minute = Int(g[2]) ?? 0
    } else if let g = match(#"(\d{1,2}):(\d{2})"#) {
        hour = Int(g[1])
        minute = Int(g[2]) ?? 0
    }
    guard let hour else { return nil }

    // 날짜: "10월 20일" > 요일 > 오늘(지났으면 내일)
    if let g = match(#"(\d{1,2})월\s*(\d{1,2})일"#), let month = Int(g[1]), let day = Int(g[2]) {
        var c = cal.dateComponents([.year], from: now)
        c.month = month; c.day = day; c.hour = hour; c.minute = minute
        guard var d = cal.date(from: c) else { return nil }
        if d < now.addingTimeInterval(-3600) { d = cal.date(byAdding: .year, value: 1, to: d) ?? d }
        return d
    }
    let korean = ["일", "월", "화", "수", "목", "금", "토"]
    let english = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    var weekday: Int?
    if let g = match(#"\((일|월|화|수|목|금|토)(?:요일)?\)|(일|월|화|수|목|금|토)요일"#) {
        weekday = korean.firstIndex(of: g[1].isEmpty ? g[2] : g[1]).map { $0 + 1 }
    } else if let g = match(#"\b(sun|mon|tue|wed|thu|fri|sat)"#) {
        weekday = english.firstIndex(of: g[1].lowercased()).map { $0 + 1 }
    }
    var c = DateComponents()
    c.hour = hour; c.minute = minute
    if let weekday { c.weekday = weekday }
    guard let next = cal.nextDate(after: now, matching: c, matchingPolicy: .nextTime) else { return nil }
    // 시각만 적혀 있는데 거의 하루 뒤로 계산되면, 그 시각이 방금 지났는데 페이지가 아직 안 바뀐 것이다
    if weekday == nil, next.timeIntervalSince(now) > 22 * 3600 { return now }
    return next
}

/// "2일 3시간", "3시간 12분", "12분"
func countdownText(until date: Date?, now: Date) -> String? {
    guard let date else { return nil }
    let s = max(0, Int(date.timeIntervalSince(now)))
    if s < 60 { return "곧" }
    let d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60
    if d > 0 { return "\(d)일 \(h)시간" }
    if h > 0 { return "\(h)시간 \(m)분" }
    return "\(max(1, m))분"
}

/// 초기화 문구 뒤에 남은 시간을 붙인다
func resetLine(_ g: LimitGauge, now: Date) -> String {
    guard let reset = g.reset else { return "초기화 시각 정보 없음" }
    guard let left = countdownText(until: nextResetDate(reset, now: now), now: now) else { return reset }
    return left == "곧" ? "\(reset) · 곧 초기화" : "\(reset) · \(left) 남음"
}
