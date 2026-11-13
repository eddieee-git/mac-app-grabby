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
    private let welcome = WelcomeWindowController()
    private let settings = AppSettings.shared
    /// 캡처를 시작하기 전에 앞에 있던 앱. 캡처가 끝나면 돌려줘서 바로 ⌘V로 붙여 넣을 수 있게 한다.
    private var previousApp: NSRunningApplication?

    private let lastRectKey = "lastCaptureRect"
    private let lastDisplayKey = "lastCaptureDisplay"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = settings.theme.appearance
        buildMainMenu()
        buildStatusItem()
        // 언어를 바꾸면 메뉴를 다시 만들고, 탭 창은 새 언어로 다시 연다.
        NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.languageChanged() }
        }
        // 설정에서 단축키를 바꾸면 바로 다시 등록한다. 입력받는 동안에는 잠시 풀어 둔다.
        hotKeySubscription = settings.$hotKeys.combineLatest(settings.$isRecordingHotKey).sink { [weak self] combos, isRecording in
            self?.registerHotKeys(isRecording ? [:] : combos)
            self?.updateHotKeyItems(combos)
        }
        _ = CaptureStore.shared
        // 날수로 정리하는 설정은 앱을 켜 둔 채로도 지나야 하므로 시작할 때와 한 시간마다 확인한다.
        CaptureStore.shared.tidy()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { _ = CaptureStore.shared.tidy() }
        }
        if settings.restorePins { PinWindow.restore() } else { PinWindow.discardSaved() }
        ScreenCapturer.warmUp()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                ScreenCapturer.invalidate()
                ScreenCapturer.warmUp()
            }
        }
        checkForUpdate()
        Updater.announceIfUpdated()
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            welcome.show()
        }
        // 다른 캡처 앱이 켜져 있으면 단축키가 겹칠 수 있다고 한 번 알려 준다.
        let others = HotKeyConflicts.runningCaptureApps
        let blocked = HotKeyConflicts.blockedBySystem(settings.hotKeys)
        if !blocked.isEmpty, UserDefaults.standard.bool(forKey: "didShowWelcome") {
            Toast.show(L("%@는 macOS 스크린샷 단축키와 겹쳐요 · 설정 > 단축키에서 확인해 주세요", blocked.joined(separator: ", ")))
        } else if !others.isEmpty {
            Toast.show(L("%@이(가) 켜져 있어요 · 단축키가 겹치면 설정에서 바꿔 주세요", others.joined(separator: ", ")))
        }
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
        case .captureFullScreen: captureFullScreen()
        case .captureWindow: captureFrontWindow()
        case .captureTimer: startTimer(seconds: settings.timerSeconds)
        case .whiteboard: openWhiteboard()
        case .readCode: readCode()
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

    func applicationWillTerminate(_ notification: Notification) {
        PinWindow.saveAll()
        CaptureStore.shared.flush()
    }

    /// 실행 중에 응용 프로그램 폴더에서 다시 열면 캡처 창을 보여 준다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openLibrary()
        return false
    }

    // MARK: 메뉴

    private func languageChanged() {
        buildMainMenu()
        buildStatusMenu()
        updateHotKeyItems(settings.hotKeys)
        guard let old = library else { return }
        let wasVisible = old.isVisible
        old.close()
        library = nil
        if wasVisible { openLibrary() }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Grabby")
        image?.isTemplate = true
        statusItem.button?.image = image
        buildStatusMenu()
    }

    private var availableUpdate: UpdateChecker.Release?

    /// 설정에서 켰을 때만 확인한다. 새 버전이 있으면 메뉴 맨 위에 알려 준다.
    @objc func checkForUpdate() { checkForUpdate(force: false) }

    /// 설정에서 방금 켰을 때는 하루를 기다리지 않고 바로 확인한다.
    @objc func checkForUpdateNow() { checkForUpdate(force: true) }

    private func checkForUpdate(force: Bool) {
        guard settings.checkUpdates else { return }
        UpdateChecker.check(force: force) { [weak self] release in
            guard let self, let release else { return }
            self.availableUpdate = release
            self.buildStatusMenu()
            #if DEBUG
            // 점검용: `-autoInstallUpdate YES`면 묻지 않고 바로 설치한다.
            if UserDefaults.standard.bool(forKey: "autoInstallUpdate") { self.startUpdate(release) }
            #endif
        }
    }

    @objc private func openReleasePage() { NSWorkspace.shared.open(UpdateChecker.releasesPage) }

    /// 메뉴의 "새 버전 설치": 물어보고 내려받아 바꿔 넣는다. 그 자리에서 바꿀 수 없으면 릴리스 페이지를 연다.
    @objc private func installUpdate() {
        guard let release = availableUpdate else { return }
        guard release.dmg != nil, release.signature != nil, Updater.canReplace(Bundle.main.bundleURL) else {
            openReleasePage()
            return
        }
        let alert = NSAlert()
        alert.messageText = L("Grabby %@로 업데이트할까요?", release.version)
        alert.informativeText = L("새 버전을 내려받아 확인한 뒤 바꿔 넣고 다시 시작해요. 화면 기록 권한을 다시 물으면 시스템 설정에서 Grabby를 껐다 켜 주세요.")
        alert.addButton(withTitle: L("업데이트"))
        alert.addButton(withTitle: L("바뀐 점 보기"))
        alert.addButton(withTitle: L("나중에"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: startUpdate(release)
        case .alertSecondButtonReturn: openReleasePage()
        default: break
        }
    }

    private func startUpdate(_ release: UpdateChecker.Release) {
        Toast.show(L("새 버전을 내려받는 중이에요…"))
        Task { @MainActor in
            defer { self.buildStatusMenu() }
            do {
                self.buildStatusMenu()
                try await Updater.install(release)
            } catch {
                let alert = NSAlert()
                alert.messageText = L("업데이트하지 못했어요")
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: L("릴리스 페이지 열기"))
                alert.addButton(withTitle: L("닫기"))
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { self.openReleasePage() }
            }
        }
    }

    private func buildStatusMenu() {
        let menu = NSMenu()
        if let release = availableUpdate {
            if Updater.isInstalling {
                let busy = NSMenuItem(title: L("새 버전 %@ 내려받는 중…", release.version), action: nil, keyEquivalent: "")
                busy.isEnabled = false
                menu.addItem(busy)
            } else {
                menu.addItem(item(L("새 버전 %@ 설치…", release.version), action: #selector(installUpdate)))
            }
            menu.addItem(.separator())
        }
        let capture = item(HotKeyAction.captureArea.title, action: #selector(captureArea))
        let repeatLast = item(HotKeyAction.repeatLastArea.title, action: #selector(repeatLastArea))
        let fullScreen = item(HotKeyAction.captureFullScreen.title, action: #selector(captureFullScreen))
        let frontWindow = item(HotKeyAction.captureWindow.title, action: #selector(captureFrontWindow))
        let whiteboard = item(HotKeyAction.whiteboard.title, action: #selector(openWhiteboard))
        let qr = item(HotKeyAction.readCode.title, action: #selector(readCode))
        hotKeyItems = [.captureArea: capture, .repeatLastArea: repeatLast, .captureFullScreen: fullScreen, .captureWindow: frontWindow, .whiteboard: whiteboard, .readCode: qr]
        menu.addItem(capture)
        menu.addItem(repeatLast)
        menu.addItem(fullScreen)
        menu.addItem(frontWindow)
        menu.addItem(whiteboard)
        menu.addItem(qr)
        let timer = NSMenuItem(title: L("타이머 캡처"), action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for seconds in [3, 5, 10] {
            let entry = item(L("%ld초 뒤", seconds), action: #selector(captureWithTimer(_:)))
            entry.tag = seconds
            timerMenu.addItem(entry)
        }
        timer.submenu = timerMenu
        menu.addItem(timer)
        let timerNow = item(L("타이머 캡처 (설정한 시간)"), action: #selector(captureWithConfiguredTimer))
        hotKeyItems[.captureTimer] = timerNow
        timerMenu.insertItem(timerNow, at: 0)
        timerMenu.insertItem(item(L("타이머 취소"), action: #selector(cancelTimer)), at: 1)
        timerMenu.insertItem(.separator(), at: 2)
        menu.addItem(.separator())
        menu.addItem(item(L("캡처 창 열기"), action: #selector(openLibrary)))
        menu.addItem(item(L("띄운 캡처 모두 닫기"), action: #selector(closeAllPins)))
        menu.addItem(.separator())
        menu.addItem(item(L("시작 안내"), action: #selector(openWelcome)))
        menu.addItem(.separator())
        let settingsItem = item(L("설정…"), action: #selector(openSettings))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Grabby 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
        let settingsItem = NSMenuItem(title: L("설정…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L("Grabby 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("편집"))
        edit.addItem(NSMenuItem(title: L("실행 취소"), action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: L("다시 실행"), action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: L("오려두기"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: L("복사"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: L("붙이기"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: L("전체 선택"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        edit.addItem(NSMenuItem(title: L("창 닫기"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        edit.addItem(NSMenuItem(title: L("저장…"), action: #selector(NSDocument.save(_:)), keyEquivalent: "s"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func openSettings() { settingsWindow.show() }
    @objc private func closeAllPins() { PinWindow.closeAll() }
    @objc private func openWelcome() { welcome.show() }

    @objc private func openLibrary() {
        if library == nil { library = LibraryWindowController() }
        library?.show()
    }

    // MARK: 캡처

    /// 화면을 멈춰 찍고 오버레이를 띄운다. 오버레이는 포커스를 빼앗지 않으므로 원래 앱이 계속 앞에 있다.
    private func startSession(_ mode: CaptureSession.Mode) {
        guard session == nil else { return }
        if mode != .whiteboard, !ScreenCapturer.hasPermission { ScreenCapturer.requestPermission(); return }
        rememberFrontApp()
        Task { @MainActor in
            var shots: [ScreenShot] = []
            do {
                if ScreenCapturer.hasPermission { shots = try await ScreenCapturer.captureAll() }
            } catch {
                if mode != .whiteboard { show(error); return }
            }
            // 화이트보드는 권한이 없으면 바깥도 바탕으로 띄운다.
            if shots.isEmpty, mode == .whiteboard {
                let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                if let screen, let board = ScreenShot.whiteboard(on: screen) { shots = [board] }
            }
            guard !shots.isEmpty, session == nil else { return }
            session = CaptureSession(shots: shots, mode: mode) { [weak self] result in
                self?.session = nil
                self?.finishCapture(result)
            }
        }
    }

    @objc private func captureArea() { startSession(.area) }
    @objc private func readCode() { startSession(.qr) }

    /// n초 뒤에 영역 캡처를 시작한다. 남은 시간을 보여 주고, 찍기 직전에 알림을 치운다.
    @objc private func captureWithTimer(_ sender: NSMenuItem) { startTimer(seconds: sender.tag) }
    @objc private func captureWithConfiguredTimer() { startTimer(seconds: settings.timerSeconds) }

    @objc private func cancelTimer() {
        guard timerRunning else { return }
        timerGeneration += 1
        timerRunning = false
        Countdown.hide()
        Toast.show(L("타이머를 취소했어요"))
    }

    /// 화면 기록 권한을 켠 뒤에는 앱을 다시 켜야 적용된다. 잠깐 뒤에 새로 열고 지금 것은 끝낸다.
    @objc func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    private var timerRunning = false
    /// 취소한 뒤 바로 다시 시작해도 이전 타이머가 이어서 세지 않도록 차례 번호로 구분한다.
    private var timerGeneration = 0

    /// 타이머 캡처. 세는 동안 타이머 단축키를 한 번 더 누르거나 메뉴의 "타이머 취소"를 누르면 멈춘다.
    private func startTimer(seconds: Int) {
        if timerRunning {
            cancelTimer()
            return
        }
        guard session == nil else { return }
        if !ScreenCapturer.hasPermission { ScreenCapturer.requestPermission(); return }
        timerRunning = true
        timerGeneration += 1
        let generation = timerGeneration
        var remaining = seconds
        Toast.hide()
        func tick() {
            guard generation == timerGeneration else { return }
            if remaining == 0 {
                Countdown.hide()
                timerRunning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.startSession(.area) }
                return
            }
            Countdown.show(remaining)
            remaining -= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick() }
        }
        tick()
    }
    /// 전체 화면 캡처: 기본은 편집 화면 없이 마우스가 있는 화면을 바로 복사하고 탭에 넣는다.
    /// 설정에서 끄면 예전처럼 편집 화면으로 연다.
    @objc private func captureFullScreen() {
        guard settings.fullScreenInstant else { startSession(.fullScreen); return }
        guard session == nil else { return }
        guard ScreenCapturer.hasPermission else { ScreenCapturer.requestPermission(); return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            startSession(.fullScreen)
            return
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        Task { @MainActor in
            do {
                guard let shot = try await ScreenCapturer.capture(displayID: displayID) else {
                    startSession(.fullScreen)
                    return
                }
                save(CaptureResult(image: shot.image, pixelScale: shot.scale,
                                   rect: CGRect(origin: .zero, size: shot.screen.frame.size),
                                   displayID: displayID, screenFrame: shot.screen.frame))
            } catch {
                show(error)
            }
        }
    }

    /// 지금 앞에 있는 앱의 맨 앞 창을 고른 채 편집 화면을 연다. 창을 못 찾으면 영역 캡처로 시작한다.
    @objc private func captureFrontWindow() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let window = WindowList.frontWindow(preferring: front) else {
            startSession(.area)
            return
        }
        startSession(.window(window.rect, window.name, window.id))
    }
    @objc private func openWhiteboard() { startSession(.whiteboard) }

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
                save(CaptureResult(image: image, pixelScale: shot.scale, rect: rect, displayID: displayID, screenFrame: shot.screen.frame))
            } catch {
                show(error)
            }
        }
    }

    /// 복사하고 탭에 넣는다. 찍은 자리를 반짝이고 소리를 낸다.
    private func save(_ result: CaptureResult, copy: Bool = true) {
        let (item, pruned) = CaptureStore.shared.add(result.image, scale: result.pixelScale,
                                                     original: result.original, annotations: result.annotations)
        if copy { Clipboard.copy(result.image, scale: result.pixelScale) }
        if !result.isWhiteboard {
            UserDefaults.standard.set(NSStringFromRect(result.rect), forKey: lastRectKey)
            UserDefaults.standard.set(Int(result.displayID), forKey: lastDisplayKey)
        }
        CaptureFeedback.flash(result.globalRect)
        let message = !copy ? L("탭에만 남겼어요 · 복사는 하지 않았어요")
            : pruned > 0 ? L("복사했어요 · 오래된 캡처 %ld개를 정리했어요", pruned) : L("복사했어요 · ⌘V로 붙여 넣기")
        Toast.show(message, image: CaptureStore.shared.thumbnail(for: item))
        if settings.openLibraryAfterCapture {
            if library == nil { library = LibraryWindowController() }
            library?.showWithoutFocus()
        }
        CaptureStore.shared.indexText()
    }

    /// 캡처·화이트보드를 마친 뒤 고른 동작을 하고 원래 앱으로 돌아간다.
    private func finishCapture(_ result: CaptureResult?) {
        guard let result else { returnToPreviousApp(); return }
        switch result.action {
        case .ocr:
            // 글자만 복사하고 탭에는 넣지 않는다.
            Task { @MainActor in
                let text = await TextRecognizer.recognize(result.image)
                if text.isEmpty {
                    Toast.show(L("글자를 찾지 못했어요"))
                } else {
                    Clipboard.copy(text: text)
                    let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
                    Toast.show(L("글자를 복사했어요 · %@", String(firstLine.prefix(40))))
                }
                returnToPreviousApp()
            }
        case .qr:
            // 값만 복사하고 탭에는 넣지 않는다.
            Task { @MainActor in
                let values = await CodeReader.read(result.image)
                returnToPreviousApp()
                CodeReader.handle(values)
            }
        case .save:
            save(result)
            ImageSaver.save(result.image, scale: result.pixelScale) { [weak self] in self?.returnToPreviousApp() }
        case .pin:
            save(result)
            PinWindow.show(result.image, scale: result.pixelScale, at: result.globalRect)
            returnToPreviousApp()
        case .copy:
            save(result)
            returnToPreviousApp()
        case .keep:
            save(result, copy: false)
            returnToPreviousApp()
        case .beautify:
            // 탭에는 원래 캡처를 넣고, 클립보드에는 꾸민 이미지를 넣는다.
            save(result)
            Clipboard.copy(Beautifier.apply(result.image, scale: result.pixelScale), scale: result.pixelScale)
            Toast.show(L("꾸며서 복사했어요"))
            returnToPreviousApp()
        }
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
        alert.messageText = L("캡처하지 못했어요")
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
