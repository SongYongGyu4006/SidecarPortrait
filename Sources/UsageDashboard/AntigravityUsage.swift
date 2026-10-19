// Antigravity 사용량: Antigravity 한도는 Gemini 앱(채팅) 한도와 따로 있고 웹 페이지가 없어서,
// 공식 Antigravity CLI(agy)의 `/usage`를 출력 모드로 실행해 읽는다. 로그인은 agy가 관리한다.
//   agy -p /usage 출력 (탭 구분, 남은 비율):
//   Gemini Models	Five Hour Limit Remaining	100%	2026-10-19T10:46:46Z
//   Gemini 4 Argon	Gemini 4 Argon Weekly Limit	93%	2026-10-25T13:53:36Z
import Foundation

/// Finder로 연 앱은 PATH가 짧아서 흔한 설치 위치를 직접 찾는다
func agyPath() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return ["\(home)/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

struct AgyRow {
    let group: String
    let name: String
    let remaining: Int
    let reset: Date?
}

func parseAgyUsage(_ text: String) -> [AgyRow] {
    let iso = ISO8601DateFormatter()
    return text.split(whereSeparator: \.isNewline).compactMap { line in
        let cols = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
        guard cols.count >= 3, cols[2].hasSuffix("%"), let value = Int(cols[2].dropLast()) else { return nil }
        return AgyRow(group: cols[0], name: cols[1], remaining: value, reset: cols.count > 3 ? iso.date(from: cols[3]) : nil)
    }
}

/// "오후 7:46에 초기화" 또는 "10월 26일 오후 2:46에 초기화". 다른 서비스와 같은 문구라 남은 시간 계산을 같이 쓴다.
func koreanResetText(_ date: Date?, now: Date = Date()) -> String? {
    guard let date else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "a h:mm" : "M월 d일 a h:mm"
    return "\(f.string(from: date))에 초기화"
}

/// 표시할 한도: 5시간 한도와 주간 한도에서 각각 가장 많이 쓴 줄(같으면 Gemini 모델 공통 한도),
/// 그다음 실제로 쓴 다른 한도 하나. 모델별 한도(예: Gemini 4 Argon 주간)가 따로 줄어들기 때문이다.
func antigravityGauges(_ rows: [AgyRow]) -> [LimitGauge] {
    func isFiveHour(_ row: AgyRow) -> Bool { row.name.localizedCaseInsensitiveContains("five hour") }
    func isWeekly(_ row: AgyRow) -> Bool { row.name.localizedCaseInsensitiveContains("week") }
    func label(_ row: AgyRow) -> String {
        let span = isFiveHour(row) ? "5시간" : isWeekly(row) ? "주간" : row.name
        if row.group == "Gemini Models" { return "Gemini \(span)" }
        if row.group.localizedCaseInsensitiveContains("claude") { return "Claude·GPT \(span)" }
        return "\(row.group) \(span)"
    }
    func gauge(_ row: AgyRow) -> LimitGauge {
        LimitGauge(label: label(row), percent: max(0, min(100, 100 - row.remaining)), reset: koreanResetText(row.reset))
    }
    func mostUsed(_ candidates: [AgyRow]) -> AgyRow? {
        candidates.min { a, b in
            a.remaining != b.remaining ? a.remaining < b.remaining : a.group == "Gemini Models" && b.group != "Gemini Models"
        }
    }
    var picked = [mostUsed(rows.filter(isFiveHour)), mostUsed(rows.filter(isWeekly))].compactMap { $0 }
    if let extra = mostUsed(rows.filter { r in r.remaining < 100 && !picked.contains { $0.group == r.group && $0.name == r.name } }) {
        picked.append(extra)
    }
    return (picked.isEmpty ? Array(rows.prefix(2)) : picked).map(gauge)
}

/// agy를 백그라운드에서 실행하고 결과를 메인 스레드로 돌려준다
func fetchAntigravity(_ completion: @escaping (AccountState, String) -> Void) {
    guard let agy = agyPath() else {
        return completion(.failed("Antigravity CLI(agy)가 설치돼 있지 않아요"), "")
    }
    DispatchQueue.global(qos: .utility).async {
        // 대화가 남지 않도록 빈 임시 폴더에서 실행한다
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("UsageDashboard-agy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agy)
        process.arguments = ["-p", "/usage", "--print-timeout", "40s"]
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var state = AccountState.failed("agy를 실행하지 못했어요")
        var text = ""
        do {
            try process.run()
            let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: killer)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            killer.cancel()
            text = String(decoding: data, as: UTF8.self)
            let gauges = antigravityGauges(parseAgyUsage(text))
            if !gauges.isEmpty {
                state = .ok(gauges, Date())
            } else if ["login", "log in", "sign in", "auth"].contains(where: { text.localizedCaseInsensitiveContains($0) }) {
                state = .needsLogin
            } else {
                state = .failed("agy 사용량 출력을 읽지 못했어요")
            }
        } catch {
            state = .failed("agy 실행 실패: \(error.localizedDescription)")
        }
        DispatchQueue.main.async { completion(state, text) }
    }
}
