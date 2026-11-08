import AppKit

MainActor.assumeIsolated {
    // 자동 점검만 돌리고 끝낸다(scripts/test.sh).
    if CommandLine.arguments.contains("--self-test") {
        _ = NSApplication.shared
        exit(SelfTest.run())
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // 메뉴바 전용 앱: Dock 아이콘을 표시하지 않는다.
    // 점검할 때는 `-showInDock YES` 인자로 실행하면 일반 앱처럼 보여서 자동화 도구가 찾을 수 있다.
    app.setActivationPolicy(UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory)
    app.run()
}
