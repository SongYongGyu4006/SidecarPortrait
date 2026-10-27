// 작은 Wi‑Fi 화면(GeekMagic SmallTV-Ultra 등 240×240)에 사용량 이미지를 보낸다.
// 기기 펌웨어는 그대로 두고, 사진 앨범 기능에 JPEG 한 장을 올린 뒤 그 이미지를 표시하게 한다.
//   POST /doUpload?dir=/image/  (multipart, 필드 이름 file)
//   GET  /set?img=/image/ai-usage.jpg
// 올릴 때마다 기기 플래시에 쓰므로, 숫자가 바뀌었을 때와 화면의 "기준" 시각이 1시간 지났을 때만 올린다.
import AppKit
import SwiftUI

enum DevicePush {
    static let fileName = "ai-usage.jpg"
    static let side: CGFloat = 240

    /// 메뉴에서 정한 기기 주소. 비어 있으면 보내지 않는다.
    static var host: String? {
        get { UserDefaults.standard.string(forKey: "deviceHost").flatMap { $0.isEmpty ? nil : $0 } }
        set { UserDefaults.standard.set(newValue ?? "", forKey: "deviceHost") }
    }

    /// 마지막으로 보낸 화면 내용. 대시보드와 백그라운드 수집기가 함께 본다.
    private static var lastSent: String? {
        get { UserDefaults.standard.string(forKey: "deviceLastSent") }
        set { UserDefaults.standard.set(newValue, forKey: "deviceLastSent") }
    }

    /// 마지막으로 보낸 시각
    private static var lastSentAt: Date? {
        get { UserDefaults.standard.object(forKey: "deviceLastSentAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "deviceLastSentAt") }
    }

    /// 값이 그대로여도 이만큼 지나면 "기준" 시각을 새로 고쳐 다시 보낸다 (하루 24번 정도라 플래시 부담이 작다)
    static let refreshInterval: TimeInterval = 3600

    /// 화면에 들어갈 값이 바뀌었거나 마지막으로 보낸 지 1시간이 지났으면 그려서 보낸다
    @MainActor static func pushIfChanged(claude: AccountState, second: AccountService, secondState: AccountState,
                                         force: Bool = false, completion: ((String) -> Void)? = nil) {
        guard let host else { completion?("기기 주소가 없어요"); return }
        let view = MiniUsageView(claude: claude, second: second, secondState: secondState, now: Date())
        let stale = lastSentAt.map { Date().timeIntervalSince($0) >= refreshInterval - 60 } ?? true
        guard force || stale || view.signature != lastSent else { completion?("바뀐 값이 없어 보내지 않았어요"); return }
        guard let jpeg = render(view) else { completion?("그리기 실패"); return }
        upload(jpeg, to: host) { error in
            DispatchQueue.main.async {
                if let error { return completion?("보내기 실패: \(error)") ?? () }
                lastSent = view.signature
                lastSentAt = Date()
                completion?("보냈어요 (\(jpeg.count / 1024)KB)")
            }
        }
    }

    @MainActor static func render(_ view: MiniUsageView) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: side, height: side).environment(\.colorScheme, .dark))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    static func upload(_ jpeg: Data, to host: String, completion: @escaping (String?) -> Void) {
        guard let uploadURL = URL(string: "http://\(host)/doUpload?dir=/image/"),
              let showURL = URL(string: "http://\(host)/set?img=" + "/image/\(fileName)".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!) else {
            return completion("주소가 올바르지 않아요")
        }
        let boundary = "UsageDashboard-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: uploadURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        URLSession.shared.uploadTask(with: request, from: body) { _, response, error in
            if let error { return completion(error.localizedDescription) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return completion("업로드 응답 \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            // 올린 이미지를 화면에 띄운다
            URLSession.shared.dataTask(with: URLRequest(url: showURL, timeoutInterval: 10)) { _, _, error in
                completion(error?.localizedDescription)
            }.resume()
        }.resume()
    }
}

/// 240×240 레트로 화면: 서비스마다 한도 두 줄(이름, %, 칸 막대, 초기화 시각)
struct MiniUsageView: View {
    let claude: AccountState
    let second: AccountService
    let secondState: AccountState
    let now: Date

    private let t = RetroTheme.dark

    /// 화면 모양을 바꾸면 올린다. 값이 같아도 새 모양을 한 번은 보내기 위해서다.
    static let design = 2

    /// 화면 내용을 대표하는 문자열. 같으면 다시 보내지 않는다.
    /// 초기화 시각은 시간 단위로만 비교한다 (안 쓴 한도는 초기화 시각이 조금씩 계속 밀리기 때문)
    var signature: String {
        "v\(Self.design)|" + [claude, secondState].map { s in
            s.gauges.prefix(2).map { g in
                let hour = nextResetDate(g.reset, now: now).map { Int($0.timeIntervalSince1970 / 3600) } ?? 0
                return "\(g.percent)@\(hour)"
            }.joined(separator: ",")
        }.joined(separator: ";") + "|\(second.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                PixelText("AI USAGE", px: 2, color: t.phosphor, glow: false)
                Spacer()
                Text(clockText(now) + " 기준").font(monoFont(10)).foregroundStyle(t.dim)
            }
            .padding(.bottom, 8)
            block(.claude, claude, t.claude)
            Rectangle().fill(t.phosphor.opacity(0.15)).frame(height: 1).padding(.vertical, 7)
            block(second, secondState, t.gemini)
        }
        .padding(10)
        .frame(width: DevicePush.side, height: DevicePush.side, alignment: .topLeading)
        .background(t.background)
    }

    func block(_ service: AccountService, _ state: AccountState, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            PixelText(service.title, px: 2, color: color, glow: false)
            let gauges = Array(state.gauges.prefix(2))
            if gauges.isEmpty {
                Text(state.notice(service)?.title ?? "값 없음").font(monoFont(11)).foregroundStyle(t.dim)
                    .frame(height: 70, alignment: .topLeading)
            }
            ForEach(Array(gauges.enumerated()), id: \.element.id) { i, g in
                let tint = g.percent >= 80 ? t.danger : color
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .bottom) {
                        PixelText(gaugeTag(g.label, index: i), px: 1.6, color: t.dim, glow: false)
                        Text(shortReset(g)).font(monoFont(9)).foregroundStyle(t.dim).lineLimit(1)
                        Spacer(minLength: 2)
                        PixelText("\(g.percent)%", px: 3, color: tint, glow: false)
                    }
                    RetroBar(fraction: Double(g.percent) / 100, color: tint)
                        .frame(height: 10)
                }
            }
        }
    }

    /// "↺ 16:20" 또는 "↺ 10/21 22:00". 남은 시간은 매분 바뀌어 매번 다시 보내게 되므로 시각만 쓴다.
    func shortReset(_ g: LimitGauge) -> String {
        guard let date = nextResetDate(g.reset, now: now) else { return "" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "HH:mm" : "M/d HH:mm"
        return "↺ " + f.string(from: date)
    }
}

/// 칸을 나누지 않고 이어지는 레트로 막대: 각진 테두리 안에 막대가 차오르고, 25% 간격으로 작은 눈금이 있다
struct RetroBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 2.5
            let inner = geo.size.width - inset * 2
            let fill = inner * CGFloat(min(1, max(0, fraction)))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(color.opacity(0.1))
                // 눈금 (채워진 부분 위에서는 어둡게 보인다)
                ForEach([0.25, 0.5, 0.75], id: \.self) { p in
                    Rectangle().fill(Color.black.opacity(0.35))
                        .frame(width: 1, height: geo.size.height - inset * 2)
                        .offset(x: inset + inner * p, y: inset)
                }
                if fill > 0 {
                    Rectangle().fill(color)
                        .frame(width: max(2, fill), height: geo.size.height - inset * 2)
                        .overlay(alignment: .top) {
                            // 윗줄을 밝게 해서 브라운관 느낌을 낸다
                            Rectangle().fill(Color.white.opacity(0.28)).frame(height: 1)
                        }
                        .offset(x: inset, y: inset)
                }
                Rectangle().strokeBorder(color.opacity(0.55), lineWidth: 1.5)
            }
        }
    }
}
