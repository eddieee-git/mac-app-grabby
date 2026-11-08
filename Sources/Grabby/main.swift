import AppKit

MainActor.assumeIsolated {
    // 자동 점검만 돌리고 끝낸다(scripts/test.sh).
    if CommandLine.arguments.contains("--self-test") {
        _ = NSApplication.shared
        exit(SelfTest.run())
    }
    // 하나만 실행: 업데이트하면서 예전 Grabby가 아직 켜져 있으면 끝내고 새로 켠 쪽이 이어받는다.
    // 두 개가 같은 보관함 목록을 서로 덮어쓰면 캡처가 목록에서 빠질 수 있어서다.
    if let id = Bundle.main.bundleIdentifier {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0 != .current }
        if !others.isEmpty {
            EventLog.write("이미 켜져 있던 Grabby(\(others.map(\.processIdentifier)))를 끝내고 이어받음")
            others.forEach { $0.terminate() }
            let deadline = Date().addingTimeInterval(3)
            while others.contains(where: { !$0.isTerminated }), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        }
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // 메뉴바 전용 앱: Dock 아이콘을 표시하지 않는다.
    // 점검할 때는 `-showInDock YES` 인자로 실행하면 일반 앱처럼 보여서 자동화 도구가 찾을 수 있다.
    #if DEBUG
    app.setActivationPolicy(UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory)
    #else
    app.setActivationPolicy(.accessory)
    #endif
    app.run()
}
