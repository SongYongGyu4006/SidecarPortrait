// SidecarPortrait
// iPad Sidecar 앱은 항상 가로 캔버스로만 그리므로, 세로 가상 디스플레이를 만들어
// 그 화면을 캡처한 뒤 가로 Sidecar 화면에 90도 돌려 꽉 차게 그린다.
// iPad는 가로 상태에서 회전 잠금을 켠 뒤 세로로 돌려 들면 된다.
//
//   swift run SidecarPortrait [--rotate 270|90] [--device "<iPad 이름>"]

import AppKit
import ScreenCaptureKit
import PrivateAPI

struct Options {
    var rotation = 270
    var device: String?

    init(_ args: [String]) {
        var it = args.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--rotate": rotation = Int(it.next() ?? "") ?? 270
            case "--device": device = it.next()
            default:
                print("사용법: SidecarPortrait [--rotate 270|90] [--device \"iPad 이름\"]")
                exit(1)
            }
        }
        guard rotation == 90 || rotation == 270 else {
            print("--rotate는 90 또는 270만 가능해요")
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
    if let failure { print("Sidecar 연결 실패: \(failure.localizedDescription)") }
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
        print("Sidecar 기기가 없어요. 같은 Apple 계정, Wi‑Fi·Bluetooth, iPad 잠금 해제를 확인해 주세요.")
        return nil
    }
    if sidecarDisplay() != nil {
        print("Sidecar가 세로로 연결돼 있어서 가로로 다시 연결해요 (\(name))")
        disconnectSidecar(name)
    } else {
        print("Sidecar 연결 중: \(name)")
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

final class Mirror: NSObject, SCStreamOutput, SCStreamDelegate {
    let window: NSWindow
    let content = CALayer()
    var stream: SCStream?

    init(frame: NSRect, portraitSize: CGSize, rotation: Int) {
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.setFrame(frame, display: false)
        window.backgroundColor = .black
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
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

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("캡처가 멈췄어요: \(error.localizedDescription)")
        NSApp.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    var virtualDisplay: SPVirtualDisplay?
    var mirror: Mirror?

    init(options: Options) { self.options = options }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let sidecar = landscapeSidecarDisplay(device: options.device) else { return fail() }
        let landscape = CGDisplayBounds(sidecar).size
        let portrait = CGSize(width: landscape.height, height: landscape.width)
        print("Sidecar 화면: \(Int(landscape.width))x\(Int(landscape.height)) → 가상 디스플레이 \(Int(portrait.width))x\(Int(portrait.height))")

        guard let virtual = SPVirtualDisplay(name: "Sidecar 세로", width: UInt32(portrait.width), height: UInt32(portrait.height), hiDPI: true) else {
            print("가상 디스플레이를 만들지 못했어요")
            return fail()
        }
        virtualDisplay = virtual
        guard waitUntil(timeout: 10, { activeDisplays().contains(virtual.displayID) }) else {
            print("가상 디스플레이가 화면 목록에 나타나지 않아요")
            return fail()
        }
        arrange(virtual: virtual.displayID, sidecar: sidecar)
        _ = waitUntil(timeout: 1) { false }

        // 배치를 바꾼 뒤의 Sidecar 좌표로 창을 만든다
        let mirror = Mirror(frame: cocoaFrame(of: sidecar), portraitSize: portrait, rotation: options.rotation)
        self.mirror = mirror
        let mode = CGDisplayCopyDisplayMode(virtual.displayID)
        let pixels = CGSize(width: mode?.pixelWidth ?? Int(portrait.width * 2), height: mode?.pixelHeight ?? Int(portrait.height * 2))
        print("가상 디스플레이 \(virtual.displayID): \(mode?.width ?? 0)x\(mode?.height ?? 0) (픽셀 \(Int(pixels.width))x\(Int(pixels.height)))")

        Task { @MainActor in
            do {
                try await mirror.start(displayID: virtual.displayID, pixelSize: pixels)
                print("미러링 시작 (회전 \(self.options.rotation)도). 창을 'Sidecar 세로' 디스플레이로 옮기세요. 종료: Ctrl+C")
            } catch {
                print("캡처 시작 실패: \(error.localizedDescription)")
                print("시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음에서 이 터미널 앱을 허용해 주세요.")
                self.fail()
            }
        }
    }

    func fail() {
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
