import AppKit
import Carbon
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var session: CaptureSession?
    private var library: LibraryWindowController?
    private var loginItem: NSMenuItem!
    /// 캡처를 시작하기 전에 앞에 있던 앱. 캡처가 끝나면 돌려줘서 바로 ⌘V로 붙여 넣을 수 있게 한다.
    private var previousApp: NSRunningApplication?

    private let lastRectKey = "lastCaptureRect"
    private let lastDisplayKey = "lastCaptureDisplay"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()
        let commandShift = cmdKey | shiftKey
        hotKeys = [
            HotKey(id: 1, keyCode: kVK_ANSI_1, modifiers: commandShift) { [weak self] in MainActor.assumeIsolated { self?.captureArea() } },
            HotKey(id: 2, keyCode: kVK_ANSI_2, modifiers: commandShift) { [weak self] in MainActor.assumeIsolated { self?.repeatLastArea() } },
        ].compactMap { $0 }
        _ = CaptureStore.shared
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
        menu.delegate = self
        menu.addItem(item("영역 캡처", key: "1", action: #selector(captureArea)))
        menu.addItem(item("마지막 영역 다시 캡처", key: "2", action: #selector(repeatLastArea)))
        menu.addItem(.separator())
        menu.addItem(item("캡처 창 열기", key: "", action: #selector(openLibrary)))
        menu.addItem(.separator())
        loginItem = item("로그인 시 실행", key: "", action: #selector(toggleLoginItem))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Grabby 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, key: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
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

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

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
        UserDefaults.standard.set(NSStringFromRect(result.rect), forKey: lastRectKey)
        UserDefaults.standard.set(Int(result.displayID), forKey: lastDisplayKey)
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
