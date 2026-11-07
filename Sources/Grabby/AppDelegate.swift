import AppKit
import Carbon
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var hotKeyItems: [HotKeyAction: NSMenuItem] = [:]
    private var hotKeySubscription: AnyCancellable?
    private var session: CaptureSession?
    private var library: LibraryWindowController?
    private let settingsWindow = SettingsWindowController()
    private let settings = AppSettings.shared
    /// 캡처를 시작하기 전에 앞에 있던 앱. 캡처가 끝나면 돌려줘서 바로 ⌘V로 붙여 넣을 수 있게 한다.
    private var previousApp: NSRunningApplication?

    private let lastRectKey = "lastCaptureRect"
    private let lastDisplayKey = "lastCaptureDisplay"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()
        // 설정에서 단축키를 바꾸면 바로 다시 등록한다. 입력받는 동안에는 잠시 풀어 둔다.
        hotKeySubscription = settings.$hotKeys.combineLatest(settings.$isRecordingHotKey).sink { [weak self] combos, isRecording in
            self?.registerHotKeys(isRecording ? [:] : combos)
            self?.updateHotKeyItems(combos)
        }
        _ = CaptureStore.shared
    }

    private func registerHotKeys(_ combos: [String: KeyCombo]) {
        hotKeys = []
        var failed: Set<HotKeyAction> = []
        for (index, action) in HotKeyAction.allCases.enumerated() {
            guard let combo = combos[action.rawValue] else { continue }
            let hotKey = HotKey(id: UInt32(index + 1), combo: combo) { [weak self] in
                MainActor.assumeIsolated { self?.perform(action) }
            }
            if let hotKey { hotKeys.append(hotKey) } else { failed.insert(action) }
        }
        settings.failedHotKeys = failed
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .captureArea: captureArea()
        case .repeatLastArea: repeatLastArea()
        case .whiteboard: openWhiteboard()
        }
    }

    /// 메뉴에 지금 단축키를 보여 준다.
    private func updateHotKeyItems(_ combos: [String: KeyCombo]) {
        for (action, item) in hotKeyItems {
            let combo = combos[action.rawValue]
            item.keyEquivalent = combo?.menuKey ?? ""
            item.keyEquivalentModifierMask = combo?.menuModifiers ?? []
        }
    }

    /// 실행 중에 응용 프로그램 폴더에서 다시 열면 캡처 창을 보여 준다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openLibrary()
        return false
    }

    // MARK: 메뉴

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Grabby")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        let capture = item(HotKeyAction.captureArea.title, action: #selector(captureArea))
        let repeatLast = item(HotKeyAction.repeatLastArea.title, action: #selector(repeatLastArea))
        let whiteboard = item(HotKeyAction.whiteboard.title, action: #selector(openWhiteboard))
        hotKeyItems = [.captureArea: capture, .repeatLastArea: repeatLast, .whiteboard: whiteboard]
        menu.addItem(capture)
        menu.addItem(repeatLast)
        menu.addItem(whiteboard)
        menu.addItem(.separator())
        menu.addItem(item("캡처 창 열기", action: #selector(openLibrary)))
        menu.addItem(.separator())
        let settingsItem = item("설정…", action: #selector(openSettings))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Grabby 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// 메뉴바 앱이라 메뉴가 보이지는 않지만, ⌘C·⌘V·⌘Z 같은 편집 단축키가 동작하려면 필요하다.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Grabby 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "편집")
        edit.addItem(NSMenuItem(title: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "붙이기", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        edit.addItem(NSMenuItem(title: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func openSettings() { settingsWindow.show() }

    @objc private func openLibrary() {
        if library == nil { library = LibraryWindowController() }
        library?.show()
    }

    // MARK: 캡처

    @objc private func captureArea() {
        guard session == nil else { return }
        guard ScreenCapturer.hasPermission else { ScreenCapturer.requestPermission(); return }
        rememberFrontApp()
        Task { @MainActor in
            do {
                let shots = try await ScreenCapturer.captureAll()
                guard !shots.isEmpty, session == nil else { return }
                NSApp.activate(ignoringOtherApps: true)
                session = CaptureSession(shots: shots) { [weak self] result in
                    self?.session = nil
                    if let result { self?.save(result) }
                    self?.returnToPreviousApp()
                }
            } catch {
                show(error)
            }
        }
    }

    /// 흰 바탕을 띄워 그리게 한다. 화면을 찍지 않으므로 화면 기록 권한이 필요 없다.
    @objc private func openWhiteboard() {
        guard session == nil else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen, let board = ScreenShot.whiteboard(on: screen) else { return }
        rememberFrontApp()
        NSApp.activate(ignoringOtherApps: true)
        session = CaptureSession(shots: [board], whiteboard: true) { [weak self] result in
            self?.session = nil
            if let result { self?.save(result) }
            self?.returnToPreviousApp()
        }
    }

    /// 마지막으로 고른 영역을 편집 없이 바로 다시 찍어 복사한다.
    @objc private func repeatLastArea() {
        guard session == nil else { return }
        let defaults = UserDefaults.standard
        guard let saved = defaults.string(forKey: lastRectKey), defaults.object(forKey: lastDisplayKey) != nil else {
            captureArea()
            return
        }
        guard ScreenCapturer.hasPermission else { ScreenCapturer.requestPermission(); return }
        let rect = NSRectFromString(saved)
        let displayID = CGDirectDisplayID(defaults.integer(forKey: lastDisplayKey))
        Task { @MainActor in
            do {
                guard let shot = try await ScreenCapturer.capture(displayID: displayID),
                      let image = shot.crop(rect.intersection(CGRect(origin: .zero, size: shot.screen.frame.size))) else {
                    captureArea()
                    return
                }
                save(CaptureResult(image: image, pixelScale: shot.scale, rect: rect, displayID: displayID))
            } catch {
                show(error)
            }
        }
    }

    private func save(_ result: CaptureResult) {
        let item = CaptureStore.shared.add(result.image, scale: result.pixelScale)
        Clipboard.copy(result.image, scale: result.pixelScale)
        if !result.isWhiteboard {
            UserDefaults.standard.set(NSStringFromRect(result.rect), forKey: lastRectKey)
            UserDefaults.standard.set(Int(result.displayID), forKey: lastDisplayKey)
        }
        Toast.show("복사했어요 · ⌘V로 붙여 넣기", image: CaptureStore.shared.thumbnail(for: item))
        if library == nil { library = LibraryWindowController() }
        library?.showWithoutFocus()
    }

    private func rememberFrontApp() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
    }

    private func returnToPreviousApp() {
        guard let previousApp else { return }
        self.previousApp = nil
        previousApp.activate()
        // 원래 앱이 앞으로 오면서 탭 창을 덮지 않도록, 포커스는 원래 앱에 둔 채 창만 다시 앞으로 올린다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.library?.showWithoutFocus()
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "캡처하지 못했어요"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
