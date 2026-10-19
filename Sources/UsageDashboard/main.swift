// UsageDashboard
// 가로로 연결한 iPad Sidecar 화면을 Claude·Antigravity(또는 Gemini) 사용량 대시보드로 꽉 채운다.
// Sidecar가 연결돼 있지 않으면 첫 번째 iPad를 가로로 연결하고, 종료할 때 그 연결을 끊는다.
//
//   swift run UsageDashboard [--device "<iPad 이름>"] [--window] [--snapshot out.png] [--style …] [--appearance …]
//     --window    Sidecar 대신 지금 화면에 일반 창으로 띄운다
//     --style retro|minimal|neon|gauge, --appearance system|light|dark  화면 스타일과 모드 (메뉴 막대에서도 고를 수 있다)
//     --snapshot  1366×1024 화면을 PNG로 저장하고 끝낸다
//     --dump-account claude|gemini|antigravity out.txt  사용량 페이지에서 읽은 글자를 저장하고 끝낸다 (파싱 확인용)
//   또는 Scripts/build-app.sh UsageDashboard로 만든 UsageDashboard.app을 실행 (메뉴 막대에서 종료)
import AppKit
import PrivateAPI
import SwiftUI

let runningAsApp = Bundle.main.bundlePath.hasSuffix(".app")
let canvas = CGSize(width: 1366, height: 1024)

struct Options {
    var device: String?
    var windowMode = false
    var snapshot: String?
    var dump: (AccountService, String)?
    var style: DashboardStyle?
    var appearance: Appearance?

    init(_ args: [String]) {
        var it = args.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--device": device = it.next()
            case "--window": windowMode = true
            case "--snapshot": snapshot = it.next()
            case "--style":
                guard let v = it.next().flatMap(DashboardStyle.init(rawValue:)) else { usage() }
                style = v
            case "--appearance":
                guard let v = it.next().flatMap(Appearance.init(rawValue:)) else { usage() }
                appearance = v
            case "--dump-account":
                guard let s = it.next().flatMap(AccountService.init(rawValue:)), let path = it.next() else {
                    print("사용법: --dump-account claude|gemini|antigravity out.txt"); exit(1)
                }
                dump = (s, path)
            default:
                if arg.hasPrefix("-psn_") { continue }  // Finder로 열 때 붙는 인자
                usage()
            }
        }
    }

    func usage() -> Never {
        print("""
        사용법: UsageDashboard [--device "iPad 이름"] [--window] [--snapshot out.png] [--dump-account claude|gemini|antigravity out.txt]
                              [--style retro|minimal|neon|gauge] [--appearance system|light|dark]
        """)
        exit(1)
    }
}

func showAlert(_ text: String) {
    if !runningAsApp { print(text); return }
    let alert = NSAlert()
    alert.messageText = "AI 사용량"
    alert.informativeText = text
    alert.runModal()
}

func sidecarScreen() -> NSScreen? {
    let id = SPSidecar.displayID()
    guard id != kCGNullDirectDisplay else { return nil }
    return NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let options: Options
    let history = UsageHistory()
    lazy var accounts = AccountStore(history: history)
    let settings = DisplaySettings()
    var window: NSWindow?
    var statusItem: NSStatusItem?
    /// 이 앱이 연결한 Sidecar 기기. 종료할 때 연결을 끊는다.
    var connectedDevice: String?

    init(options: Options) { self.options = options }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if options.snapshot != nil { settings.persist = false }
        if let style = options.style { settings.style = style }
        if let appearance = options.appearance { settings.appearance = appearance }
        if let path = options.snapshot { return saveSnapshot(to: path) }
        if let (service, path) = options.dump { return dumpAccount(service, to: path) }
        addStatusItem()
        accounts.start()
        if options.windowMode {
            showWindowed()
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                                   name: NSApplication.didChangeScreenParametersNotification, object: nil)
            showOnSidecar()
        }
    }

    func makeWindow(frame: NSRect, borderless: Bool) -> NSWindow {
        let w = NSWindow(contentRect: frame, styleMask: borderless ? [.borderless] : [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: DashboardView(accounts: accounts, history: history, settings: settings))
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        w.title = "AI 사용량"
        return w
    }

    func showWindowed() {
        let w = makeWindow(frame: NSRect(origin: .zero, size: CGSize(width: canvas.width * 0.75, height: canvas.height * 0.75)), borderless: false)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    func showOnSidecar() {
        if let screen = sidecarScreen() { return place(on: screen) }
        guard let name = options.device ?? SPSidecar.deviceNames().first else {
            showAlert("Sidecar로 쓸 iPad가 없어요. 같은 Apple 계정, Wi‑Fi·Bluetooth, iPad 잠금 해제를 확인해 주세요.\n\n지금은 이 화면에 창으로 띄울게요.")
            return showWindowed()
        }
        print("Sidecar 연결 중: \(name)")
        SPSidecar.connectDevice(name, size: .zero, scale: 2) { error in
            DispatchQueue.main.async {
                if let error {
                    showAlert("Sidecar 연결 실패: \(error.localizedDescription)\n\n지금은 이 화면에 창으로 띄울게요.")
                    return self.showWindowed()
                }
                self.connectedDevice = name
                // 창은 화면 목록이 바뀔 때(screensChanged) 옮긴다
                self.screensChanged()
            }
        }
    }

    /// Sidecar 화면 전체를 덮는다. 다른 디스플레이 메뉴 막대도 가리도록 메뉴 막대보다 위에 둔다.
    func place(on screen: NSScreen) {
        let w = window ?? makeWindow(frame: screen.frame, borderless: true)
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
        print("Sidecar 화면에 표시: \(Int(screen.frame.width))x\(Int(screen.frame.height))")
    }

    @objc func screensChanged() {
        if let screen = sidecarScreen() {
            place(on: screen)
        } else {
            window?.orderOut(nil)  // iPad 연결이 끊기면 다시 연결될 때까지 숨긴다
        }
    }

    @objc func refreshNow() { accounts.refresh() }

    @objc func login(_ sender: NSMenuItem) {
        guard let service = sender.representedObject as? String, let s = AccountService(rawValue: service) else { return }
        accounts.showLogin(s)
    }

    @objc func logout(_ sender: NSMenuItem) {
        guard let service = sender.representedObject as? String, let s = AccountService(rawValue: service) else { return }
        accounts.logout(s)
    }

    @objc func reconnect() {
        if options.windowMode { return }
        showOnSidecar()
    }

    func addStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "AI 사용량")
        let menu = NSMenu()
        menu.addItem(withTitle: "AI 사용량", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "지금 새로고침", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(choiceMenu("화면 스타일 (iPad 화면을 탭해도 바뀌어요)", DashboardStyle.allCases.map { ($0.title, $0.rawValue) }, #selector(pickStyle(_:))))
        menu.addItem(choiceMenu("화면 모드", Appearance.allCases.map { ($0.title, $0.rawValue) }, #selector(pickAppearance(_:))))
        menu.addItem(.separator())
        menu.addItem(choiceMenu("오른쪽 칸", [(AccountService.antigravity.title, AccountService.antigravity.rawValue),
                                                ("Gemini 앱(채팅)", AccountService.gemini.rawValue)], #selector(pickSecond(_:))))
        menu.addItem(.separator())
        for service in AccountService.web {
            let login = menu.addItem(withTitle: "\(service.title) 로그인…", action: #selector(login(_:)), keyEquivalent: "")
            login.target = self
            login.representedObject = service.rawValue
        }
        for service in AccountService.web {
            let logout = menu.addItem(withTitle: "\(service.title) 로그아웃", action: #selector(logout(_:)), keyEquivalent: "")
            logout.target = self
            logout.representedObject = service.rawValue
        }
        if !options.windowMode {
            menu.addItem(withTitle: "iPad에 다시 표시", action: #selector(reconnect), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func choiceMenu(_ title: String, _ choices: [(String, String)], _ action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, value) in choices {
            let item = sub.addItem(withTitle: label, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = value
        }
        parent.submenu = sub
        return parent
    }

    @objc func pickStyle(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let style = DashboardStyle(rawValue: v) { settings.style = style }
    }

    @objc func pickSecond(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let s = AccountService(rawValue: v) { settings.second = s }
    }

    @objc func pickAppearance(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let a = Appearance(rawValue: v) { settings.appearance = a }
    }

    /// 메뉴를 열 때 지금 고른 스타일·모드에 체크 표시를 한다 (iPad 탭으로도 바뀌므로)
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            for sub in item.submenu?.items ?? [] {
                let v = sub.representedObject as? String
                sub.state = [settings.style.rawValue, settings.appearance.rawValue, settings.second.rawValue].contains(v ?? "") ? .on : .off
            }
        }
    }

    /// 화면 없이 확인할 수 있도록 iPad 크기로 그려 PNG로 저장한다
    func saveSnapshot(to path: String) {
        accounts.refresh()
        waitForSnapshot(to: path, deadline: Date(timeIntervalSinceNow: 40))
    }

    /// 계정 한도를 다 읽을 때까지(최대 40초) 기다렸다가 그린다
    func waitForSnapshot(to path: String, deadline: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            let accountsLoading = AccountService.allCases.contains { accounts.state($0) == .loading }
            if accountsLoading && Date() < deadline { return waitForSnapshot(to: path, deadline: deadline) }
            let view = DashboardView(accounts: accounts, history: history, settings: settings).frame(width: canvas.width, height: canvas.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                print("그리기 실패"); exit(1)
            }
            try? png.write(to: URL(fileURLWithPath: path))
            print("저장: \(path)")
            exit(0)
        }
    }

    func dumpAccount(_ service: AccountService, to path: String) {
        accounts.refresh(service) { [self] text in
            let state = accounts.state(service)
            try? "상태: \(state)\n\n\(text)".write(toFile: path, atomically: true, encoding: .utf8)
            print("저장: \(path) (\(state))")
            exit(0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let name = connectedDevice else { return }
        let done = DispatchSemaphore(value: 0)
        SPSidecar.disconnectDevice(name) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 5)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate(options: Options(CommandLine.arguments)) }
app.delegate = delegate
app.setActivationPolicy(.accessory)

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { NSApp.terminate(nil) }
sigint.resume()

app.run()
