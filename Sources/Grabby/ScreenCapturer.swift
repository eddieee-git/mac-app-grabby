import AppKit
import ScreenCaptureKit

/// 한 화면을 통째로 찍은 이미지. 영역 선택은 이 멈춘 화면 위에서 한다.
struct ScreenShot {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let image: CGImage

    /// 이미지 픽셀 수 / 화면 포인트 수
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }

    /// 화면 왼쪽 위 기준 포인트 좌표의 영역을 잘라낸다.
    func crop(_ rect: CGRect) -> CGImage? {
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale).integral
        return image.cropping(to: pixels)
    }
}

extension ScreenShot {
    /// 화면 크기만 한 흰 바탕. 화면 기록 권한이 없을 때 화이트보드 바깥 배경으로 쓴다.
    static func whiteboard(on screen: NSScreen) -> ScreenShot? {
        let scale = screen.backingScaleFactor
        guard let image = white(width: Int(screen.frame.width * scale), height: Int(screen.frame.height * scale)) else { return nil }
        return ScreenShot(screen: screen, displayID: screen.displayID, image: image)
    }

    /// 화이트보드 바탕. 모눈과 줄 간격은 포인트 기준이라 레티나에서도 같은 크기로 보인다.
    static func board(_ style: AppSettings.BoardStyle, width: Int, height: Int, scale: CGFloat) -> CGImage? {
        guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        let background = style == .dark ? CGColor(srgbRed: 0.17, green: 0.2, blue: 0.19, alpha: 1) : CGColor(gray: 1, alpha: 1)
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.setLineWidth(max(1, scale * 0.5))
        switch style {
        case .grid:
            let step = 20 * scale
            context.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.88, blue: 0.92, alpha: 1))
            var x: CGFloat = step
            while x < w { context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: h)); x += step }
            var y: CGFloat = h - step
            while y > 0 { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: w, y: y)); y -= step }
            context.strokePath()
        case .lines:
            let step = 28 * scale
            context.setStrokeColor(CGColor(srgbRed: 0.78, green: 0.84, blue: 0.93, alpha: 1))
            var y: CGFloat = h - step
            while y > 0 { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: w, y: y)); y -= step }
            context.strokePath()
        case .white, .dark:
            break
        }
        return context.makeImage()
    }

    static func white(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// 화면에 떠 있는 일반 창들의 영역. 클릭 한 번으로 창 하나를 고를 때 쓴다.
enum WindowList {
    /// 앞에 있는 창부터, 지정한 화면 왼쪽 위 기준 포인트 좌표로 돌려준다. Grabby 자신의 창은 뺀다.
    static func rects(on displayID: CGDirectDisplayID) -> [CGRect] { windows(on: displayID).map(\.rect) }

    /// 창 영역과 그 창의 앱 이름.
    struct ScreenWindow: Equatable {
        let rect: CGRect
        let name: String
    }

    static func windows(on displayID: CGDirectDisplayID) -> [ScreenWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let screen = CGDisplayBounds(displayID)
        return info.compactMap { window in
            // 일반 창(0)과 떠 있는 창(Floaty 스티커 같은 3 등)은 고르고, Dock·메뉴바(20 이상)는 뺀다.
            guard let layer = window[kCGWindowLayer as String] as? Int, (0..<20).contains(layer),
                  (window[kCGWindowOwnerPID as String] as? pid_t) != me,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 40, rect.height >= 40 else { return nil }
            let visible = rect.intersection(screen)
            guard !visible.isNull, visible.width >= 40, visible.height >= 40 else { return nil }
            let name = window[kCGWindowOwnerName as String] as? String ?? ""
            return ScreenWindow(rect: visible.offsetBy(dx: -screen.minX, dy: -screen.minY).integral, name: name)
        }
    }
}

extension WindowList {
    /// 앱의 맨 앞 창 영역(전역 좌표, 왼쪽 위 원점). 창이 없으면 nil.
    static func frontWindow(of pid: pid_t) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in info {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, (0..<20).contains(layer),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 40, rect.height >= 40 else { continue }
            return rect
        }
        return nil
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

@MainActor
enum ScreenCapturer {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// 권한을 처음 요청할 때만 시스템 창이 뜬다. 이미 거절했으면 시스템 설정으로 안내한다.
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = L("화면 기록 권한이 필요해요")
        alert.informativeText = L("시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 기록에서 Grabby를 켠 뒤, Grabby를 다시 실행해 주세요.")
        alert.addButton(withTitle: L("시스템 설정 열기"))
        alert.addButton(withTitle: L("닫기"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 연결된 모든 화면을 찍는다.
    /// 화면 목록은 자주 바뀌지 않으므로 한 번 받아 두고 쓴다. 화면 구성이 바뀌면 `invalidate()`로 버린다.
    private static var cachedContent: SCShareableContent?

    static func content(refresh: Bool = false) async throws -> SCShareableContent {
        if !refresh, let cachedContent { return cachedContent }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = content
        return content
    }

    static func invalidate() { cachedContent = nil }

    /// 단축키를 처음 눌렀을 때 늦지 않도록 미리 화면 목록을 받아 둔다.
    static func warmUp() {
        guard hasPermission else { return }
        Task { _ = try? await content(refresh: true) }
    }

    /// 모든 화면을 동시에 찍는다. 받아 둔 목록이 낡아 실패하면 새로 받아 한 번 더 찍는다.
    static func captureAll() async throws -> [ScreenShot] {
        do {
            return try await captureDisplays(try await content())
        } catch {
            return try await captureDisplays(try await content(refresh: true))
        }
    }

    private static func captureDisplays(_ content: SCShareableContent) async throws -> [ScreenShot] {
        let displays = content.displays
        return try await withThrowingTaskGroup(of: (Int, ScreenShot?).self) { group in
            for (index, display) in displays.enumerated() {
                group.addTask { @MainActor in (index, try await capture(display)) }
            }
            var shots: [(Int, ScreenShot)] = []
            for try await (index, shot) in group { if let shot { shots.append((index, shot)) } }
            return shots.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// 지정한 화면만 찍는다. 화면이 연결되어 있지 않으면 nil.
    static func capture(displayID: CGDirectDisplayID) async throws -> ScreenShot? {
        let content = try await content()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        return try await capture(display)
    }

    private static func capture(_ display: SCDisplay) async throws -> ScreenShot? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { return nil }
        let scale = screen.backingScaleFactor, frame = screen.frame
        let config = SCStreamConfiguration()
        config.width = Int(frame.width * scale)
        config.height = Int(frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return ScreenShot(screen: screen, displayID: display.displayID, image: image)
    }
}
