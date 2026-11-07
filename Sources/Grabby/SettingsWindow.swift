import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// 바뀌는 즉시 저장되는 설정.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard
    private let hotKeysKey = "hotKeys"
    private let knownActionsKey = "knownHotKeyActions"

    /// 전역 단축키. 키는 `HotKeyAction.rawValue`이고, 없는 동작은 단축키를 쓰지 않는다.
    @Published var hotKeys: [String: KeyCombo] {
        didSet { defaults.set(try? JSONEncoder().encode(hotKeys), forKey: hotKeysKey) }
    }
    /// 단축키를 입력받는 동안에는 전역 단축키를 잠시 풀어 둔다.
    @Published var isRecordingHotKey = false
    @Published var failedHotKeys: Set<HotKeyAction> = []

    private init() {
        var saved = defaults.data(forKey: hotKeysKey).flatMap { try? JSONDecoder().decode([String: KeyCombo].self, from: $0) }
            ?? KeyCombo.defaults
        // 나중에 추가된 동작은 한 번만 기본 단축키를 넣어 준다. 사용자가 지운 단축키는 되살리지 않는다.
        var known = Set(defaults.stringArray(forKey: knownActionsKey) ?? Array(saved.keys))
        for action in HotKeyAction.allCases where !known.contains(action.rawValue) {
            if saved[action.rawValue] == nil, let combo = KeyCombo.defaults[action.rawValue],
               !saved.values.contains(combo) { saved[action.rawValue] = combo }
            known.insert(action.rawValue)
        }
        hotKeys = saved
        defaults.set(Array(known), forKey: knownActionsKey)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Grabby 설정"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: .shared))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("단축키") {
                HotKeyEditor(settings: settings)
            }
            Section("일반") {
                Toggle("로그인 시 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}

/// 전역 단축키를 입력받는다. 버튼을 누른 다음 원하는 조합을 누르면 저장한다.
private struct HotKeyEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var recording: HotKeyAction?
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        ForEach(HotKeyAction.allCases, id: \.self) { action in
            LabeledContent(action.title) {
                HStack(spacing: 8) {
                    if settings.failedHotKeys.contains(action) {
                        Text("등록하지 못함").font(.caption).foregroundStyle(.red)
                    }
                    Button(recording == action ? "키를 누르세요" : settings.hotKeys[action.rawValue]?.displayText ?? "없음") {
                        recording == action ? stop() : start(action)
                    }
                    .frame(minWidth: 110)
                    Button {
                        settings.hotKeys[action.rawValue] = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.hotKeys[action.rawValue] == nil)
                    .help("단축키 지우기")
                }
            }
        }
        HStack {
            Text(message ?? "다른 캡처 앱과 겹치면 먼저 등록한 앱이 키를 받아요. Esc로 입력 취소.")
                .font(.caption)
                .foregroundStyle(message == nil ? Color.secondary : Color.red)
            Spacer()
            Button("기본값으로") {
                stop()
                settings.hotKeys = KeyCombo.defaults
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start(_ action: HotKeyAction) {
        stop()
        recording = action
        settings.isRecordingHotKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: action)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        message = nil
        if settings.isRecordingHotKey { settings.isRecordingHotKey = false }
    }

    private func handle(_ event: NSEvent, for action: HotKeyAction) {
        if event.keyCode == 53 { // Esc
            stop()
            return
        }
        guard let combo = KeyCombo(event: event) else {
            message = "⌘, ⌃, ⌥ 중 하나와 함께 누르세요."
            return
        }
        if let other = HotKeyAction.allCases.first(where: { $0 != action && settings.hotKeys[$0.rawValue] == combo }) {
            message = "\(other.title)에서 쓰는 단축키예요."
            return
        }
        settings.hotKeys[action.rawValue] = combo
        stop()
    }
}
