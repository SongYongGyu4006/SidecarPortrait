// 화면 스타일·라이트/다크 모드 설정과, 모든 스타일이 함께 쓰는 화면 데이터
import SwiftUI

enum DashboardStyle: String, CaseIterable, Identifiable {
    case retro, minimal, neon, gauge
    var id: String { rawValue }

    var title: String {
        switch self {
        case .retro: return "레트로 픽셀"
        case .minimal: return "미니멀"
        case .neon: return "네온 사이버펑크"
        case .gauge: return "자동차 계기판"
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "시스템 설정 따르기"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }
}

/// 고른 스타일과 모드는 UserDefaults에 저장해 다음 실행에도 쓴다
final class DisplaySettings: ObservableObject {
    @Published var style: DashboardStyle { didSet { save() } }
    @Published var appearance: Appearance { didSet { save() } }
    /// 스냅숏처럼 한 번만 바꿔 볼 때는 저장하지 않는다
    var persist = true

    init() {
        let d = UserDefaults.standard
        style = d.string(forKey: "style").flatMap(DashboardStyle.init(rawValue:)) ?? .retro
        appearance = d.string(forKey: "appearance").flatMap(Appearance.init(rawValue:)) ?? .dark
    }

    func nextStyle() {
        let all = DashboardStyle.allCases
        style = all[(all.firstIndex(of: style)! + 1) % all.count]
    }

    private func save() {
        guard persist else { return }
        UserDefaults.standard.set(style.rawValue, forKey: "style")
        UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
    }
}

/// 한 번 그릴 때 필요한 값 모음
struct DashboardModel {
    let claude: AccountState
    let gemini: AccountState
    let localClaude: ServiceSummary
    let localGemini: ServiceSummary
    let now: Date
    /// 1초마다 바뀐다 (깜빡이는 커서·시계 콜론용)
    let blink: Bool

    func state(_ s: AccountService) -> AccountState { s == .claude ? claude : gemini }
    func local(_ s: AccountService) -> ServiceSummary { s == .claude ? localClaude : localGemini }
}

extension AccountState {
    var gauges: [LimitGauge] {
        if case .ok(let g, _) = self { return Array(g.prefix(3)) }
        return []
    }

    func statusText(now: Date) -> String {
        switch self {
        case .loading: return "확인 중"
        case .needsLogin: return "로그인 필요"
        case .failed: return "읽기 실패"
        case .ok(_, let date):
            let minutes = Int(now.timeIntervalSince(date) / 60)
            return minutes < 1 ? "방금 확인" : "\(minutes)분 전 확인"
        }
    }

    /// 한도를 못 보여줄 때의 안내. 정상이면 nil.
    func notice(_ service: AccountService) -> (title: String, detail: String)? {
        switch self {
        case .ok: return nil
        case .loading: return ("불러오는 중", "사용량 페이지를 읽고 있어요")
        case .needsLogin: return ("로그인이 필요해요", "Mac 메뉴 막대의 대시보드 아이콘 → \(service.title) 로그인…")
        case .failed(let reason): return (reason, "메뉴 막대에서 새로고침해 보세요")
        }
    }
}

func compact(_ n: Int) -> String {
    let v = Double(n)
    switch v {
    case 1e9...: return String(format: "%.2fB", v / 1e9)
    case 1e6...: return String(format: "%.1fM", v / 1e6)
    case 1e3...: return String(format: "%.1fK", v / 1e3)
    default: return "\(n)"
    }
}

/// 로케일과 상관없이 24시간제로 쓴다
func hourText(_ date: Date) -> String { "\(Calendar.current.component(.hour, from: date))시" }

func clockText(_ date: Date, colon: Bool = true) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: colon ? "%02d:%02d" : "%02d %02d", c.hour ?? 0, c.minute ?? 0)
}

func dateText(_ date: Date) -> String {
    date.formatted(.dateTime.month().day().weekday(.wide))
}

/// 페이지의 한도 이름을 짧은 영어 태그로 바꾼다
func gaugeTag(_ label: String, index: Int) -> String {
    let l = label.lowercased()
    if l.contains("주") || l.contains("week") { return "WEEK" }
    if l.contains("세션") || l.contains("현재") || l.contains("session") || l.contains("current") { return "NOW" }
    return "LIMIT \(index + 1)"
}

/// 고른 모드를 SwiftUI 색 구성으로 바꾼다. 시스템이면 원래 값을 그대로 쓴다.
struct AppearanceScope<Content: View>: View {
    @Environment(\.colorScheme) private var system
    let appearance: Appearance
    @ViewBuilder var content: Content

    var body: some View {
        content.environment(\.colorScheme, appearance == .light ? .light : appearance == .dark ? .dark : system)
    }
}

struct DashboardView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var accounts: AccountStore
    @ObservedObject var settings: DisplaySettings

    var body: some View {
        AppearanceScope(appearance: settings.appearance) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let model = DashboardModel(
                    claude: accounts.state(.claude), gemini: accounts.state(.gemini),
                    localClaude: store.snapshot.claude, localGemini: store.snapshot.gemini,
                    now: context.date, blink: Int(context.date.timeIntervalSince1970) % 2 == 0)
                Group {
                    switch settings.style {
                    case .retro: RetroDashboard(m: model)
                    case .minimal: MinimalDashboard(m: model)
                    case .neon: NeonDashboard(m: model)
                    case .gauge: GaugeDashboard(m: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // iPad 화면을 탭하면 다음 스타일로 바꾼다
                .onTapGesture { settings.nextStyle() }
            }
        }
    }
}
