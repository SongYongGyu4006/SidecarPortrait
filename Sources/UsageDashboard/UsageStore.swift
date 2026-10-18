// Claude Code·Gemini CLI가 로컬에 남기는 대화 기록에서 토큰 사용량을 모은다.
//   Claude: ~/.claude/projects/**/*.jsonl  (assistant 메시지의 message.usage)
//   Gemini: ~/.gemini/tmp/*/chats/*.json   (gemini 메시지의 tokens)
// 서버의 실제 한도·잔량은 알 수 없으므로 기록에 남은 토큰만 센다.
import Foundation

struct TokenCount {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    static func + (a: TokenCount, b: TokenCount) -> TokenCount {
        TokenCount(input: a.input + b.input, output: a.output + b.output,
                   cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }
    static func += (a: inout TokenCount, b: TokenCount) { a = a + b }
}

struct UsageEvent {
    let date: Date
    let model: String
    let tokens: TokenCount
}

struct ServiceSummary {
    var today = TokenCount()
    var todayMessages = 0
    var week = TokenCount()
    var weekMessages = 0
    /// 최근 24시간, 한 시간 단위 (오래된 것부터)
    var hourly: [(hour: Date, tokens: Int)] = []
    /// 최근 7일, 하루 단위 (오래된 것부터)
    var daily: [(day: Date, tokens: Int)] = []
    var lastActivity: Date?

    init() {}

    init(events: [UsageEvent], now: Date) {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let weekStart = cal.date(byAdding: .day, value: -6, to: startOfToday)!
        let thisHour = cal.dateInterval(of: .hour, for: now)!.start
        let hours = (0..<24).map { cal.date(byAdding: .hour, value: $0 - 23, to: thisHour)! }
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekStart)! }
        var hourTotals = [Date: Int]()
        var dayTotals = [Date: Int]()

        for e in events where e.date >= weekStart && e.date <= now {
            week += e.tokens
            weekMessages += 1
            dayTotals[cal.startOfDay(for: e.date), default: 0] += e.tokens.total
            if e.date >= startOfToday {
                today += e.tokens
                todayMessages += 1
            }
            if e.date >= hours[0] {
                hourTotals[cal.dateInterval(of: .hour, for: e.date)!.start, default: 0] += e.tokens.total
            }
        }
        hourly = hours.map { ($0, hourTotals[$0] ?? 0) }
        daily = days.map { ($0, dayTotals[$0] ?? 0) }
        lastActivity = events.map(\.date).max()
    }
}

struct UsageSnapshot {
    var claude = ServiceSummary()
    var gemini = ServiceSummary()
    var updated = Date()
}

private func parseDate(_ text: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: text) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: text)
}

private func modificationDate(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
}

private func files(under root: URL, withExtension ext: String) -> [URL] {
    guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
    return e.compactMap { $0 as? URL }.filter { $0.pathExtension == ext }
}

/// jsonl은 덧붙이기만 하므로 파일마다 읽은 위치를 기억해 새로 붙은 줄만 읽는다
final class ClaudeLogReader {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    private var offsets = [URL: UInt64]()
    /// 스트리밍 중 같은 응답이 여러 줄로 기록되므로 메시지 ID·요청 ID로 한 번만 센다
    private var events = [String: UsageEvent]()
    private let marker = Data("\"usage\"".utf8)

    func refresh(since cutoff: Date) -> [UsageEvent] {
        for url in files(under: root, withExtension: "jsonl") where modificationDate(url) >= cutoff {
            read(url)
        }
        events = events.filter { $0.value.date >= cutoff }
        return Array(events.values)
    }

    private func read(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var offset = offsets[url] ?? 0
        if size < offset { offset = 0 }  // 파일이 새로 쓰였으면 처음부터
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return }
        // 아직 다 쓰이지 않은 마지막 줄은 다음 번에 읽는다
        let complete = data[data.startIndex...lastNewline]
        offsets[url] = offset + UInt64(complete.count)
        for line in complete.split(separator: 0x0A) where line.range(of: marker) != nil {
            parse(Data(line))
        }
    }

    private func parse(_ line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stamp = obj["timestamp"] as? String, let date = parseDate(stamp) else { return }
        let model = message["model"] as? String ?? "unknown"
        if model == "<synthetic>" { return }
        let id = "\(message["id"] as? String ?? UUID().uuidString):\(obj["requestId"] as? String ?? "")"
        let tokens = TokenCount(input: usage["input_tokens"] as? Int ?? 0,
                                output: usage["output_tokens"] as? Int ?? 0,
                                cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
                                cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0)
        events[id] = UsageEvent(date: date, model: model, tokens: tokens)
    }
}

/// Gemini CLI는 세션마다 JSON 파일 하나를 통째로 다시 쓰므로 바뀐 파일만 다시 읽는다
final class GeminiLogReader {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/tmp")
    private var cache = [URL: (modified: Date, events: [String: UsageEvent])]()

    func refresh(since cutoff: Date) -> [UsageEvent] {
        var seen = Set<URL>()
        for url in files(under: root, withExtension: "json") where url.deletingLastPathComponent().lastPathComponent == "chats" {
            let modified = modificationDate(url)
            guard modified >= cutoff else { continue }
            seen.insert(url)
            if cache[url]?.modified != modified { cache[url] = (modified, parse(url)) }
        }
        cache = cache.filter { seen.contains($0.key) }
        // 같은 세션 파일이 여러 프로젝트 폴더에 복사돼 있기도 해서 메시지 ID로 합친다
        var merged = [String: UsageEvent]()
        for entry in cache.values { merged.merge(entry.events) { a, _ in a } }
        return merged.values.filter { $0.date >= cutoff }
    }

    private func parse(_ url: URL) -> [String: UsageEvent] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = obj["messages"] as? [[String: Any]] else { return [:] }
        var result = [String: UsageEvent]()
        for m in messages where m["type"] as? String == "gemini" {
            guard let t = m["tokens"] as? [String: Any],
                  let stamp = m["timestamp"] as? String, let date = parseDate(stamp) else { continue }
            let input = t["input"] as? Int ?? 0
            let cached = t["cached"] as? Int ?? 0
            // Gemini의 input에는 캐시 적중분이 포함돼 있다
            let tokens = TokenCount(input: max(0, input - cached) + (t["tool"] as? Int ?? 0),
                                    output: (t["output"] as? Int ?? 0) + (t["thoughts"] as? Int ?? 0),
                                    cacheRead: cached)
            let id = m["id"] as? String ?? UUID().uuidString
            result[id] = UsageEvent(date: date, model: m["model"] as? String ?? "gemini", tokens: tokens)
        }
        return result
    }
}

final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var loading = true

    private let claude = ClaudeLogReader()
    private let gemini = GeminiLogReader()
    private let queue = DispatchQueue(label: "UsageStore")
    private var timer: Timer?

    func start(interval: TimeInterval = 30) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        queue.async { [self] in
            let now = Date()
            // 7일 그래프에 필요한 만큼만 남긴다
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: now))!
            let snapshot = UsageSnapshot(
                claude: ServiceSummary(events: claude.refresh(since: cutoff), now: now),
                gemini: ServiceSummary(events: gemini.refresh(since: cutoff), now: now),
                updated: now)
            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.loading = false
            }
        }
    }
}
