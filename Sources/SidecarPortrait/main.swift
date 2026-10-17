// SidecarPortrait
// iPad Sidecar 앱은 항상 가로 캔버스로만 그리므로, 세로 가상 디스플레이를 만들어
// 그 화면을 캡처한 뒤 가로 Sidecar 화면에 90도 돌려 꽉 차게 그린다.
// iPad는 가로 상태에서 회전 잠금을 켠 뒤 세로로 돌려 들면 된다.
// iPad 터치·펜슬 입력은 회전을 되돌려 가상 디스플레이로 다시 보내고,
// 일반 마우스 커서는 실제 Sidecar 디스플레이로 넘어가지 못하게 막는다.
//
//   swift run SidecarPortrait [--rotate 270|90] [--device "<iPad 이름>"] [--debug-input]
//   또는 Scripts/build-app.sh로 만든 SidecarPortrait.app을 실행 (메뉴 막대에서 종료)

import AppKit
import ScreenCaptureKit
import PrivateAPI

/// .app으로 실행했는지. 이때는 터미널 출력이 보이지 않으므로 알림창과 메뉴 막대를 쓴다.
let runningAsApp = Bundle.main.bundleURL.pathExtension == "app"
/// 권한을 줘야 하는 대상. 터미널에서 실행하면 터미널 앱이 권한을 받는다.
let permissionTarget = runningAsApp ? "SidecarPortrait" : "이 터미널 앱"
var messages: [String] = []

/// 터미널에 출력하고, 앱으로 실행했을 때 실패 알림창에 보여 주도록 모아 둔다
func say(_ message: String) {
    print(message)
    messages.append(message)
}

/// 시스템 설정의 개인정보 보호 항목을 연다 (예: "Privacy_ScreenCapture", "Privacy_Accessibility")
func openPrivacySettings(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
}

func showAlert(_ text: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Sidecar 세로"
    alert.informativeText = text
    alert.runModal()
}

struct Options {
    // .app에서는 인자 대신 `defaults write io.github.songyonggyu4006.SidecarPortrait rotate -int 90`으로도 정할 수 있다
    var rotation = [90, 270].contains(UserDefaults.standard.integer(forKey: "rotate")) ? UserDefaults.standard.integer(forKey: "rotate") : 270
    var device: String?
    var debugInput = false

    init(_ args: [String]) {
        var it = args.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--rotate": rotation = Int(it.next() ?? "") ?? 270
            case "-rotate": _ = it.next() // UserDefaults 인자 형식
            case "--device": device = it.next()
            case "--debug-input": debugInput = true
            default:
                say("사용법: SidecarPortrait [--rotate 270|90] [--device \"iPad 이름\"] [--debug-input]")
                exit(1)
            }
        }
        guard rotation == 90 || rotation == 270 else {
            say("--rotate는 90 또는 270만 가능해요")
            exit(1)
        }
    }
}

// 앱 시작 중에는 NSScreen 목록이 갱신되지 않으므로 디스플레이는 CoreGraphics로 다룬다

func activeDisplays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

func sidecarDisplay() -> CGDirectDisplayID? {
    let id = SPSidecar.displayID()
    return id != kCGNullDirectDisplay && activeDisplays().contains(id) ? id : nil
}

/// CoreGraphics 전역 좌표(왼쪽 위 원점)를 Cocoa 창 좌표(왼쪽 아래 원점)로 바꾼다
func cocoaFrame(of display: CGDirectDisplayID) -> NSRect {
    let b = CGDisplayBounds(display)
    let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
    return NSRect(x: b.minX, y: mainHeight - b.maxY, width: b.width, height: b.height)
}

/// 화면 구성이 바뀔 때까지 런루프를 돌리며 기다린다
func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let limit = Date(timeIntervalSinceNow: timeout)
    while !condition() {
        if Date() > limit { return false }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    }
    return true
}

func connectSidecar(_ name: String, size: CGSize) -> Bool {
    var finished = false
    var failure: Error?
    SPSidecar.connectDevice(name, size: size, scale: 2) { error in
        failure = error
        finished = true
    }
    _ = waitUntil(timeout: 30) { finished }
    if let failure { say("Sidecar 연결 실패: \(failure.localizedDescription)") }
    return finished && failure == nil
}

func disconnectSidecar(_ name: String) {
    var finished = false
    SPSidecar.disconnectDevice(name) { _ in finished = true }
    _ = waitUntil(timeout: 15) { finished }
    _ = waitUntil(timeout: 10) { sidecarDisplay() == nil }
}

/// Sidecar가 가로로 연결된 디스플레이를 돌려준다. 연결이 없거나 세로면 가로로 (다시) 연결한다.
func landscapeSidecarDisplay(device: String?) -> CGDirectDisplayID? {
    // iPad Pro 12.9인치 기본 해상도. 다른 iPad는 시스템이 알아서 맞춘다.
    let landscape = CGSize(width: 1366, height: 1024)
    if let id = sidecarDisplay(), CGDisplayBounds(id).width > CGDisplayBounds(id).height { return id }

    // 연결된 기기의 이름은 따로 알 수 없어서 --device나 첫 번째 기기를 쓴다
    guard let name = device ?? SPSidecar.deviceNames().first else {
        say("Sidecar 기기가 없어요. 같은 Apple 계정, Wi‑Fi·Bluetooth, iPad 잠금 해제를 확인해 주세요.")
        return nil
    }
    if sidecarDisplay() != nil {
        say("Sidecar가 세로로 연결돼 있어서 가로로 다시 연결해요 (\(name))")
        disconnectSidecar(name)
    } else {
        say("Sidecar 연결 중: \(name)")
    }
    guard connectSidecar(name, size: landscape) else { return nil }
    _ = waitUntil(timeout: 10) { sidecarDisplay() != nil }
    return sidecarDisplay()
}

/// 가상 디스플레이를 메인 디스플레이 오른쪽에, Sidecar 디스플레이는 그 오른쪽 끝에 둔다
func arrange(virtual: CGDirectDisplayID, sidecar: CGDirectDisplayID) {
    let main = CGDisplayBounds(CGMainDisplayID())
    let vb = CGDisplayBounds(virtual)
    var config: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&config)
    CGConfigureDisplayOrigin(config, virtual, Int32(main.maxX), 0)
    CGConfigureDisplayOrigin(config, sidecar, Int32(main.maxX + vb.width), 0)
    CGCompleteDisplayConfiguration(config, .forSession)
}

// MARK: - 입력 좌표 변환

/// 미러링 창 좌표(왼쪽 아래 원점, 가로 W×H)를 세로 가상 디스플레이 안의 좌표(왼쪽 위 원점, H×W)로 바꾼다.
/// 270도: 레이어를 반시계로 90도 돌려 그리므로 창 왼쪽 아래가 세로 화면 왼쪽 위다.
/// 90도: 시계로 90도 돌려 그리므로 창 오른쪽 위가 세로 화면 왼쪽 위다.
func portraitPoint(_ p: CGPoint, windowSize s: CGSize, rotation: Int) -> CGPoint {
    rotation == 90 ? CGPoint(x: s.height - p.y, y: s.width - p.x) : CGPoint(x: p.y, y: p.x)
}

/// 창 화면 기준(아래쪽이 +y) 방향 벡터를 세로 화면 기준으로 돌린다. 스크롤 양에 쓴다.
func portraitVector(dx: Double, dy: Double, rotation: Int) -> (dx: Double, dy: Double) {
    rotation == 90 ? (dy, -dx) : (-dy, dx)
}

/// 우리가 다시 보낸 이벤트 표시. 이벤트 탭이 이것은 건드리지 않는다.
let forwardedEventMarker: Int64 = 0x5343_5054 // "SCPT"

/// 미러링 창은 클릭돼도 앱을 활성화하거나 키 창이 되지 않아야 원래 앱의 포커스가 유지된다
final class MirrorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 미러링 창으로 들어오는 마우스 이벤트(= iPad 터치·펜슬)를 모두 넘겨준다
final class InputView: NSView {
    var onEvent: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseDown(with event: NSEvent) { onEvent?(event) }
    override func mouseDragged(with event: NSEvent) { onEvent?(event) }
    override func mouseUp(with event: NSEvent) { onEvent?(event) }
    override func mouseMoved(with event: NSEvent) { onEvent?(event) }
    override func rightMouseDown(with event: NSEvent) { onEvent?(event) }
    override func rightMouseDragged(with event: NSEvent) { onEvent?(event) }
    override func rightMouseUp(with event: NSEvent) { onEvent?(event) }
    override func otherMouseDown(with event: NSEvent) { onEvent?(event) }
    override func otherMouseDragged(with event: NSEvent) { onEvent?(event) }
    override func otherMouseUp(with event: NSEvent) { onEvent?(event) }
    override func scrollWheel(with event: NSEvent) { onEvent?(event) }
}

/// 일반 마우스 커서가 실제 Sidecar 디스플레이로 넘어가면 가상 디스플레이 가장자리로 되돌린다.
/// iPad 터치·펜슬은 Sidecar 화면 아무 곳에나 바로 찍히므로 그대로 미러링 창에 보낸다.
final class CursorFence {
    let sidecar: CGRect
    let virtual: CGRect
    let debug: Bool
    private var tap: CFMachPort?
    /// 이 탭이 마지막으로 본 커서 위치 (되돌렸으면 되돌린 위치)
    private var lastLocation: CGPoint?
    private let source: CGEventSource? = {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        return source
    }()

    init(sidecar: CGRect, virtual: CGRect, debug: Bool) {
        self.sidecar = sidecar
        self.virtual = virtual
        self.debug = debug
    }

    /// 손쉬운 사용 권한이 없으면 탭을 만들 수 없어 false를 돌려준다
    func start() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                Unmanaged<CursorFence>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let loc = event.location
        let last = lastLocation ?? CGEvent(source: nil)?.location ?? loc
        lastLocation = loc
        guard sidecar.contains(loc), event.getIntegerValueField(.eventSourceUserData) != forwardedEventMarker else { return pass }

        let subtype = event.getIntegerValueField(.mouseEventSubtype)
        let isTablet = subtype == Int64(CGEventMouseSubtype.tabletPoint.rawValue)
            || subtype == Int64(CGEventMouseSubtype.tabletProximity.rawValue)
        let isDown = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
        // 일반 마우스는 Sidecar 밖에서 조금씩 이어서 들어온다. iPad 입력은 미러링 창이 곧바로
        // 가상 디스플레이로 다시 보내므로, 그 직전 커서는 Sidecar 화면과 동떨어진 곳에 있다.
        // 이벤트의 delta는 가속·되돌리기 때문에 실제 커서 이동과 어긋나서, 직접 기록한 직전 위치와 비교한다.
        let jump = hypot(loc.x - last.x, loc.y - last.y)
        let isMouseCrossing = !isTablet && !isDown && !sidecar.contains(last) && jump <= 160

        if debug {
            let dx = event.getDoubleValueField(.mouseEventDeltaX)
            let dy = event.getDoubleValueField(.mouseEventDeltaY)
            // iPad와 마우스를 구분할 단서를 찾기 위해 0이 아닌 정수 필드를 모두 찍는다
            let fields = (0..<200).compactMap { n -> String? in
                guard let field = CGEventField(rawValue: UInt32(n)) else { return nil }
                let v = event.getIntegerValueField(field)
                return v == 0 ? nil : "\(n):\(v)"
            }.joined(separator: " ")
            print("[입력] type=\(type.rawValue) loc=(\(Int(loc.x)),\(Int(loc.y))) 직전=(\(Int(last.x)),\(Int(last.y))) delta=(\(dx),\(dy)) → \(isMouseCrossing ? "마우스, 되돌림" : "iPad 입력")")
            print("       필드 \(fields)")
        }
        guard isMouseCrossing else { return pass }

        let clamped = CGPoint(x: min(max(loc.x, virtual.minX), virtual.maxX - 1),
                              y: min(max(loc.y, virtual.minY), virtual.maxY - 1))
        // CGWarpMouseCursorPosition은 매번 0.25초 동안 마우스 입력을 억제해서, 계속 밀면 커서가 얼어붙는다.
        // 대신 원래 이벤트를 버리고, 억제 시간이 0인 소스로 되돌린 위치의 이동 이벤트를 다시 보낸다.
        lastLocation = clamped
        let button: CGMouseButton = type == .rightMouseDragged ? .right : type == .otherMouseDragged ? .center : .left
        if let moved = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: clamped, mouseButton: button) {
            moved.setIntegerValueField(.eventSourceUserData, value: forwardedEventMarker)
            moved.post(tap: .cghidEventTap)
        }
        return nil
    }
}

// MARK: - 미러링

final class Mirror: NSObject, SCStreamOutput, SCStreamDelegate {
    let window: NSWindow
    let content = CALayer()
    let rotation: Int
    var stream: SCStream?
    /// 입력을 다시 보낼 가상 디스플레이의 전역 좌표. nil이면 입력 변환을 하지 않는다.
    var inputTarget: CGRect?
    var debugInput = false

    init(frame: NSRect, portraitSize: CGSize, rotation: Int) {
        let panel = MirrorPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        window = panel
        self.rotation = rotation
        super.init()
        window.setFrame(frame, display: false)
        window.backgroundColor = .black
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let root = InputView(frame: NSRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        root.onEvent = { [weak self] in self?.forward($0) }
        window.contentView = root

        // 세로 크기의 레이어를 가운데 두고 돌리면 가로 화면을 꽉 채운다
        content.bounds = CGRect(origin: .zero, size: portraitSize)
        content.position = CGPoint(x: frame.width / 2, y: frame.height / 2)
        content.contentsGravity = .resize
        content.setAffineTransform(CGAffineTransform(rotationAngle: rotation == 90 ? -.pi / 2 : .pi / 2))
        root.layer?.addSublayer(content)
        window.orderFrontRegardless()
    }

    func start(displayID: CGDirectDisplayID, pixelSize: CGSize) async throws {
        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = shareable.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "SidecarPortrait", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "캡처할 가상 디스플레이를 찾지 못했어요"])
        }
        let config = SCStreamConfiguration()
        config.width = Int(pixelSize.width)
        config.height = Int(pixelSize.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 5

        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        self.stream = stream
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // 변화가 없는 프레임(idle 등)은 이미지가 없으므로 건너뛴다
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.contents = surface
        CATransaction.commit()
    }

    /// 미러링 창 이벤트를 세로 가상 디스플레이 위치로 옮겨 다시 보낸다.
    /// 원래 이벤트를 복사하므로 클릭 횟수, 펜슬 압력 같은 값은 그대로 유지된다.
    func forward(_ event: NSEvent) {
        guard let target = inputTarget, let cg = event.cgEvent?.copy() else { return }
        let p = portraitPoint(event.locationInWindow, windowSize: window.frame.size, rotation: rotation)
        cg.location = CGPoint(x: target.minX + min(max(p.x, 0), target.width - 1),
                              y: target.minY + min(max(p.y, 0), target.height - 1))

        if event.type == .scrollWheel {
            // 스크롤 축 1은 세로, 2는 가로. 창 기준 방향을 세로 화면 기준으로 돌린다.
            let pairs: [(CGEventField, CGEventField)] = [
                (.scrollWheelEventDeltaAxis2, .scrollWheelEventDeltaAxis1),
                (.scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis1),
                (.scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis1),
            ]
            for (xField, yField) in pairs {
                if xField == .scrollWheelEventFixedPtDeltaAxis2 {
                    let v = portraitVector(dx: cg.getDoubleValueField(xField), dy: cg.getDoubleValueField(yField), rotation: rotation)
                    cg.setDoubleValueField(xField, value: v.dx)
                    cg.setDoubleValueField(yField, value: v.dy)
                } else {
                    let v = portraitVector(dx: Double(cg.getIntegerValueField(xField)), dy: Double(cg.getIntegerValueField(yField)), rotation: rotation)
                    cg.setIntegerValueField(xField, value: Int64(v.dx))
                    cg.setIntegerValueField(yField, value: Int64(v.dy))
                }
            }
        }
        if debugInput {
            let w = event.locationInWindow
            print("[전달] \(event.type.rawValue) 창(\(Int(w.x)),\(Int(w.y))) → 가상(\(Int(cg.location.x)),\(Int(cg.location.y)))")
        }
        cg.setIntegerValueField(.eventSourceUserData, value: forwardedEventMarker)
        cg.post(tap: .cghidEventTap)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        say("캡처가 멈췄어요: \(error.localizedDescription)")
        if runningAsApp { showAlert(messages.last ?? "") }
        NSApp.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    var virtualDisplay: SPVirtualDisplay?
    var mirror: Mirror?
    var fence: CursorFence?
    var statusItem: NSStatusItem?

    init(options: Options) { self.options = options }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if runningAsApp { addStatusItem() }
        // 실행 루프가 돌기 시작한 뒤에 시작한다 (알림창·메뉴 막대가 이벤트를 받을 수 있도록)
        DispatchQueue.main.async { self.start() }
    }

    func start() {
        guard let sidecar = landscapeSidecarDisplay(device: options.device) else { return fail() }
        let landscape = CGDisplayBounds(sidecar).size
        let portrait = CGSize(width: landscape.height, height: landscape.width)
        say("Sidecar 화면: \(Int(landscape.width))x\(Int(landscape.height)) → 가상 디스플레이 \(Int(portrait.width))x\(Int(portrait.height))")

        guard let virtual = SPVirtualDisplay(name: "Sidecar 세로", width: UInt32(portrait.width), height: UInt32(portrait.height), hiDPI: true) else {
            say("가상 디스플레이를 만들지 못했어요. SidecarPortrait가 이미 실행 중이면 먼저 종료해 주세요.")
            return fail()
        }
        virtualDisplay = virtual
        guard waitUntil(timeout: 10, { activeDisplays().contains(virtual.displayID) }) else {
            say("가상 디스플레이가 화면 목록에 나타나지 않아요")
            return fail()
        }
        arrange(virtual: virtual.displayID, sidecar: sidecar)
        _ = waitUntil(timeout: 1) { false }

        // 배치를 바꾼 뒤의 Sidecar 좌표로 창을 만든다
        let mirror = Mirror(frame: cocoaFrame(of: sidecar), portraitSize: portrait, rotation: options.rotation)
        self.mirror = mirror
        startInput(mirror: mirror, virtual: CGDisplayBounds(virtual.displayID), sidecar: CGDisplayBounds(sidecar))
        let mode = CGDisplayCopyDisplayMode(virtual.displayID)
        let pixels = CGSize(width: mode?.pixelWidth ?? Int(portrait.width * 2), height: mode?.pixelHeight ?? Int(portrait.height * 2))
        say("가상 디스플레이 \(virtual.displayID): \(mode?.width ?? 0)x\(mode?.height ?? 0) (픽셀 \(Int(pixels.width))x\(Int(pixels.height)))")

        Task { @MainActor in
            do {
                try await mirror.start(displayID: virtual.displayID, pixelSize: pixels)
                say("미러링 시작 (회전 \(self.options.rotation)도). 창을 'Sidecar 세로' 디스플레이로 옮기세요. 종료: \(runningAsApp ? "메뉴 막대 아이콘" : "Ctrl+C")")
            } catch {
                say("캡처 시작 실패: \(error.localizedDescription)")
                say("시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음에서 \(permissionTarget)을(를) 허용해 주세요.")
                if runningAsApp { openPrivacySettings("Privacy_ScreenCapture") }
                self.fail()
            }
        }
    }

    /// Dock 아이콘이 없으므로 메뉴 막대 아이콘으로 종료한다
    func addStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "ipad", accessibilityDescription: "Sidecar 세로")
        let menu = NSMenu()
        menu.addItem(withTitle: "Sidecar 세로 (회전 \(options.rotation)도)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// 입력 변환과 커서 가두기는 손쉬운 사용 권한이 있어야 한다. 없으면 화면 미러링만 한다.
    func startInput(mirror: Mirror, virtual: CGRect, sidecar: CGRect) {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else {
            say("손쉬운 사용 권한이 없어서 iPad 터치·펜슬 입력 변환과 커서 가두기를 끕니다.")
            say("시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 \(permissionTarget)을(를) 허용한 뒤 다시 실행해 주세요.")
            if runningAsApp { showAlert(messages.suffix(2).joined(separator: "\n\n")) }
            return
        }
        mirror.inputTarget = virtual
        mirror.debugInput = options.debugInput
        let fence = CursorFence(sidecar: sidecar, virtual: virtual, debug: options.debugInput)
        if fence.start() {
            self.fence = fence
        } else {
            say("이벤트 탭을 만들지 못해서 마우스 커서가 Sidecar 화면으로 넘어갈 수 있어요.")
        }
    }

    func fail() {
        if runningAsApp { showAlert(messages.joined(separator: "\n")) }
        NSApp.terminate(nil)
        exit(1)
    }

    func applicationWillTerminate(_ notification: Notification) {
        mirror?.stream?.stopCapture { _ in }
        virtualDisplay = nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(options: Options(CommandLine.arguments))
app.delegate = delegate
app.setActivationPolicy(.accessory)

// Ctrl+C로 끝낼 때도 가상 디스플레이를 정리한다
signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { NSApp.terminate(nil) }
sigint.resume()

app.run()
