import AppKit

/// 탭 창·설정 창처럼 제목 막대가 있는 창이 열려 있는 동안만 일반 앱으로 바꾼다.
///
/// 평소 Grabby는 Dock에 안 나오는 메뉴바 앱(.accessory)이다. 이 모드에서는 창이 앞에 있어도
/// macOS가 왼쪽 위 메뉴 막대를 주지 않아서, 탭 창을 보는 동안에도 다른 앱의 메뉴가 그대로 보였다.
/// 창이 키 창이 되면 .regular로 바꿔 Grabby 메뉴·Dock 아이콘·⌘Tab에 나오게 하고,
/// 그런 창이 모두 닫히면 다시 .accessory로 돌아간다.
/// 캡처 화면·띄운 캡처·저장 대화 상자 같은 NSPanel은 세지 않는다(잠깐 뜨거나 포커스를 빼앗지 않아야 해서).
@MainActor
final class AppPresence {
    static let shared = AppPresence()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { AppPresence.shared.windowBecameKey(window) }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { AppPresence.shared.windowWillClose(window) }
        }
    }

    /// 메뉴 막대를 가질 만한 창인지. 패널(캡처 화면, 띄운 캡처, 알림, 저장 대화 상자)은 뺀다.
    static func counts(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }

    /// Dock으로 내려 둔 창도 열린 것으로 친다. 메뉴바 앱으로 돌아가면 Dock에서 다시 꺼낼 수 없어서다.
    static func isOpen(_ window: NSWindow) -> Bool {
        counts(window) && (window.isVisible || window.isMiniaturized)
    }

    /// `-showInDock YES`로 켠 점검용 빌드는 늘 일반 앱으로 둔다.
    private var alwaysRegular: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "showInDock")
        #else
        return false
        #endif
    }

    private func windowBecameKey(_ window: NSWindow?) {
        guard let window, Self.counts(window), NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        EventLog.write("일반 앱으로 바꿈(\(type(of: window)) \"\(window.title)\")")
        // 모드를 바꾼 직후에는 메뉴 막대가 바로 바뀌지 않을 때가 있어 한 번 더 앞으로 가져온다.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func windowWillClose(_ window: NSWindow?) {
        guard let window, Self.counts(window), !alwaysRegular else { return }
        // 닫히는 창은 아직 보이는 상태라 빼고 센다.
        let others = NSApp.windows.contains { $0 !== window && Self.isOpen($0) }
        guard !others, NSApp.activationPolicy() == .regular else { return }
        // 창이 완전히 닫힌 뒤에 바꿔야 닫히는 모습이 끊기지 않는다.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let stillNone = !NSApp.windows.contains { AppPresence.isOpen($0) }
                guard stillNone else { return }
                NSApp.setActivationPolicy(.accessory)
                EventLog.write("메뉴바 앱으로 돌아감(\(type(of: window)) \"\(window.title)\" 닫힘)")
            }
        }
    }
}
