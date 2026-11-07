import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // 메뉴바 전용 앱: Dock 아이콘을 표시하지 않는다.
    app.setActivationPolicy(.accessory)
    app.run()
}
