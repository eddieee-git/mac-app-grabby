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
    /// 화면 크기만 한 흰 바탕. 화이트보드에 쓴다.
    static func whiteboard(on screen: NSScreen) -> ScreenShot? {
        let scale = screen.backingScaleFactor
        let width = Int(screen.frame.width * scale), height = Int(screen.frame.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        return ScreenShot(screen: screen, displayID: screen.displayID, image: image)
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
        alert.messageText = "화면 기록 권한이 필요해요"
        alert.informativeText = "시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 기록에서 Grabby를 켠 뒤, Grabby를 다시 실행해 주세요."
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "닫기")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 연결된 모든 화면을 찍는다.
    static func captureAll() async throws -> [ScreenShot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var shots: [ScreenShot] = []
        for display in content.displays {
            if let shot = try await capture(display) { shots.append(shot) }
        }
        return shots
    }

    /// 지정한 화면만 찍는다. 화면이 연결되어 있지 않으면 nil.
    static func capture(displayID: CGDirectDisplayID) async throws -> ScreenShot? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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
