// 계정 단위 사용량: 각 서비스의 공식 사용량 페이지를 보이지 않는 웹 뷰로 열어
// "n% 사용됨"과 초기화 시각만 읽는다. 로그인은 사용자가 로그인 창에서 직접 하고,
// 로그인 정보(쿠키)는 서비스별 전용 웹 저장소에만 남는다.
import AppKit
import WebKit

enum AccountService: String, CaseIterable, Identifiable {
    case claude, gemini, antigravity
    var id: String { rawValue }

    /// 사용량 페이지를 웹 뷰로 읽는 서비스 (Antigravity는 agy로 읽는다)
    static let web: [AccountService] = [.claude, .gemini]

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .antigravity: return "Antigravity"
        }
    }

    var loginURL: URL {
        URL(string: self == .claude ? "https://claude.ai/login" : "https://gemini.google.com/app")!
    }

    /// `defaults write io.github.songyonggyu4006.UsageDashboard geminiUsageURL <주소>`로 바꿀 수 있다
    var usageURL: URL {
        if let custom = UserDefaults.standard.string(forKey: "\(rawValue)UsageURL"), let url = URL(string: custom) { return url }
        return URL(string: self == .claude ? "https://claude.ai/settings/usage" : "https://gemini.google.com/usage")!
    }

    /// 서비스마다 따로 쓰는 웹 저장소. 값은 고정이어야 다시 실행해도 로그인이 유지된다.
    @MainActor var dataStore: WKWebsiteDataStore {
        if let store = Self.stores[self] { return store }
        let id = UUID(uuidString: self == .claude ? "6E1C1A0D-6B1F-4C55-9C0B-2F3A7C1D0001"
                                  : self == .gemini ? "6E1C1A0D-6B1F-4C55-9C0B-2F3A7C1D0002" : "6E1C1A0D-6B1F-4C55-9C0B-2F3A7C1D0003")!
        let store = WKWebsiteDataStore(forIdentifier: id)
        Self.stores[self] = store
        return store
    }
    @MainActor private static var stores = [AccountService: WKWebsiteDataStore]()

    /// 로그인 페이지로 넘어갔는지
    func isLoginPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        let s = url.absoluteString
        return s.contains("/login") || s.contains("accounts.google.com") || s.contains("appleid.apple.com")
    }
}

/// 내장 웹 뷰가 앱용 웹 뷰로 보이면 Google 로그인이 막히므로 Safari처럼 보이게 한다
let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

@MainActor func makeWebView(for service: AccountService, frame: NSRect = NSRect(x: 0, y: 0, width: 1200, height: 900)) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = service.dataStore
    let view = WKWebView(frame: frame, configuration: config)
    view.customUserAgent = safariUserAgent
    return view
}

struct LimitGauge: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let percent: Int
    let reset: String?
}

enum AccountState: Equatable {
    case loading
    case needsLogin
    case ok([LimitGauge], Date)
    case failed(String)
}

/// 페이지 글자에서 "7% 사용됨" 같은 줄을 찾고, 그 항목의 이름과 초기화 시각을 고른다
func parseLimits(_ text: String) -> [LimitGauge] {
    let lines = text.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let percentPattern = try! NSRegularExpression(pattern: #"(\d{1,3})\s*%\s*(사용됨|사용|used)"#, options: [.caseInsensitive])
    let resetWords = ["초기화", "재설정", "reset", "Reset"]
    func isReset(_ s: String) -> Bool { resetWords.contains { s.contains($0) } }
    func percent(in s: String) -> Int? {
        guard let m = percentPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return Int(s[r])
    }

    // 한 항목은 "이름 줄"부터 다음 항목 이름 줄 전까지다. 초기화 문구는 % 줄 위나 아래 어디에나 올 수 있다.
    let percentLines = lines.indices.filter { percent(in: lines[$0]) != nil }
    var labelLines = [Int]()
    for (n, i) in percentLines.enumerated() {
        let floor = n > 0 ? percentLines[n - 1] + 1 : 0
        let label = stride(from: i - 1, through: max(floor, i - 3), by: -1).first {
            let l = lines[$0]
            return l.count <= 24 && !isReset(l) && l.rangeOfCharacter(from: .letters) != nil
        }
        labelLines.append(label ?? i)
    }
    var result = [LimitGauge]()
    for (n, i) in percentLines.enumerated() {
        let start = labelLines[n]
        let end = n + 1 < labelLines.count ? labelLines[n + 1] : min(lines.count, i + 3)
        let reset = (start..<max(start, end)).map { lines[$0] }.first(where: isReset)
        let label = start < i ? lines[start] : "사용량 \(n + 1)"
        if result.contains(where: { $0.label == label }) { continue }
        result.append(LimitGauge(label: label, percent: min(100, percent(in: lines[i]) ?? 0), reset: reset))
    }
    return result
}

/// 사용량 페이지 하나를 열고 글자를 읽어 온다. 단일 페이지 앱이라 다 그려질 때까지 몇 번 다시 읽는다.
@MainActor final class AccountFetcher: NSObject, WKNavigationDelegate {
    let service: AccountService
    let webView: WKWebView
    private var completion: ((AccountState, String) -> Void)?
    private var attempts = 0

    init(service: AccountService) {
        self.service = service
        webView = makeWebView(for: service)
        super.init()
        webView.navigationDelegate = self
    }

    func fetch(_ completion: @escaping (AccountState, String) -> Void) {
        self.completion = completion
        attempts = 0
        webView.load(URLRequest(url: service.usageURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.read() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failed(error.localizedDescription), "")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failed(error.localizedDescription), "")
    }

    private func read() {
        guard completion != nil else { return }
        attempts += 1
        webView.evaluateJavaScript("location.href + '\\n' + document.body.innerText") { [weak self] value, _ in
            guard let self, self.completion != nil else { return }
            let text = value as? String ?? ""
            let gauges = parseLimits(text)
            if !gauges.isEmpty {
                self.finish(.ok(gauges, Date()), text)
            } else if self.service.isLoginPage(self.webView.url) {
                self.finish(.needsLogin, text)
            } else if self.attempts >= 8 {
                self.finish(.failed("사용량 표시를 찾지 못했어요"), text)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.read() }
            }
        }
    }

    /// 웹 뷰를 닫아 WebKit 보조 프로세스(WebContent)도 함께 끝나게 한다
    func close() {
        completion = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    private func finish(_ state: AccountState, _ text: String) {
        let done = completion
        completion = nil
        webView.stopLoading()
        done?(state, text)
    }
}

@MainActor final class AccountStore: ObservableObject {
    @Published private(set) var states: [AccountService: AccountState] = [:]
    /// 읽어 온 한도를 추이 그래프용으로 기록한다
    let history: UsageHistory
    /// 지금 읽는 중인 웹 뷰. 다 읽으면 닫아서 WebContent 프로세스와 메모리를 돌려준다.
    /// (같은 웹 뷰에 claude.ai를 계속 다시 불러오면 메모리가 1GB 가까이 불어난다)
    private var fetchers = [AccountService: AccountFetcher]()
    private var timer: Timer?
    private var loginWindows = [AccountService: NSWindow]()

    init(history: UsageHistory) { self.history = history }

    func start(interval: TimeInterval = 300) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func state(_ service: AccountService) -> AccountState { states[service] ?? .loading }

    /// 수집기처럼 곧 끝나는 프로세스는 웹 뷰를 먼저 닫아야 WebContent 프로세스가 남지 않는다
    func closeWebViews() {
        fetchers.values.forEach { $0.close() }
        fetchers.removeAll()
    }

    /// 읽을 서비스: Claude와, 오른쪽 칸에 고른 서비스(기본 Antigravity). 보지 않는 Gemini 페이지는 읽지 않는다.
    /// 백그라운드 수집기도 같은 설정(UserDefaults)을 쓴다.
    var activeServices: [AccountService] {
        let second = UserDefaults.standard.string(forKey: "second").flatMap(AccountService.init(rawValue:))
        return [.claude, second == .gemini ? .gemini : .antigravity]
    }

    /// 읽는 중인 서비스가 있는지 (스냅숏·수집기가 기다릴 때 쓴다)
    var isLoading: Bool { activeServices.contains { state($0) == .loading } }

    func refresh() {
        for service in activeServices { refresh(service) }
    }

    func refresh(_ service: AccountService, dump: ((String) -> Void)? = nil) {
        if case .ok = state(service) {} else { states[service] = .loading }
        let handle: (AccountState, String) -> Void = { [weak self] state, text in
            guard let self else { return }
            // 일시적인 실패로 이미 읽은 값을 지우지 않는다
            if case .failed = state, case .ok = self.state(service) {} else { self.states[service] = state }
            if case .ok(let gauges, let date) = state { self.history.record(service, gauges: gauges, at: date) }
            dump?(text)
        }
        if service == .antigravity { return fetchAntigravity(handle) }
        guard fetchers[service] == nil else { return }  // 아직 읽는 중이면 겹쳐 열지 않는다
        let fetcher = AccountFetcher(service: service)
        fetchers[service] = fetcher
        fetcher.fetch { [weak self] state, text in
            fetcher.close()
            self?.fetchers[service] = nil
            handle(state, text)
        }
    }

    /// 사용자가 직접 로그인하는 창. 닫으면 사용량을 다시 읽는다.
    func showLogin(_ service: AccountService) {
        if let w = loginWindows[service] {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let frame = NSRect(x: 0, y: 0, width: 520, height: 760)
        let web = makeWebView(for: service, frame: frame)
        let w = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "\(service.title) 로그인 · 다 되면 창을 닫으세요"
        w.contentView = web
        w.isReleasedWhenClosed = false
        w.center()
        web.load(URLRequest(url: service.loginURL))
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.loginWindows[service] = nil
                self?.refresh(service)
            }
        }
        loginWindows[service] = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 로그인 정보를 지운다
    func logout(_ service: AccountService) {
        let store = service.dataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in self?.states[service] = .needsLogin }
        }
    }
}
