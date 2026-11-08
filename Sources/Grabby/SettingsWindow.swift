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

    enum Theme: String, CaseIterable {
        case light, dark, system

        var title: String {
            switch self {
            case .light: return L("라이트")
            case .dark: return L("다크")
            case .system: return L("시스템")
            }
        }

        /// nil이면 시스템 설정을 따른다.
        var appearance: NSAppearance? {
            switch self {
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            case .system: return nil
            }
        }
    }

    /// 화이트보드 바탕.
    enum BoardStyle: String, CaseIterable {
        case white, grid, lines, dark

        var title: String {
            switch self {
            case .white: return L("흰색")
            case .grid: return L("모눈")
            case .lines: return L("줄")
            case .dark: return L("칠판")
            }
        }
    }

    /// 캡처 화면 도구 막대 모양.
    enum ToolbarLayout: String, CaseIterable {
        case twoRows, oneRow
        var title: String { self == .twoRows ? L("두 줄") : L("한 줄") }
    }

    /// 도구 막대를 고른 영역의 어디에 맞출지.
    enum ToolbarAlignment: String, CaseIterable {
        case center, trailing
        var title: String { self == .center ? L("가운데") : L("오른쪽") }
    }

    enum SaveFormat: String, CaseIterable {
        case png, jpeg

        var title: String { self == .png ? "PNG" : "JPEG" }
        var fileExtension: String { self == .png ? "png" : "jpg" }
    }

    /// 전역 단축키. 키는 `HotKeyAction.rawValue`이고, 없는 동작은 단축키를 쓰지 않는다.
    @Published var hotKeys: [String: KeyCombo] {
        didSet { defaults.set(try? JSONEncoder().encode(hotKeys), forKey: hotKeysKey) }
    }
    /// 단축키를 입력받는 동안에는 전역 단축키를 잠시 풀어 둔다.
    @Published var isRecordingHotKey = false
    @Published var failedHotKeys: Set<HotKeyAction> = []

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Localization.key)
            Localization.language = language
        }
    }
    @Published var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            NSApp.appearance = theme.appearance
        }
    }
    @Published var confirmDelete: Bool { didSet { defaults.set(!confirmDelete, forKey: "skipDeleteConfirmation") } }

    /// 저장 창이 처음 여는 폴더이자, 바로 저장할 때 쓰는 폴더.
    @Published var saveFolder: URL { didSet { defaults.set(saveFolder.path, forKey: "saveFolder") } }
    @Published var saveFormat: SaveFormat { didSet { defaults.set(saveFormat.rawValue, forKey: "saveFormat") } }
    @Published var saveWithoutPanel: Bool { didSet { defaults.set(saveWithoutPanel, forKey: "saveWithoutPanel") } }

    /// 편집 기본값. 색과 굵기는 `AnnotationCanvas.palette`, `lineWidths`의 번호다.
    @Published var defaultColorIndex: Int { didSet { defaults.set(defaultColorIndex, forKey: "defaultColorIndex") } }
    @Published var defaultWidthIndex: Int { didSet { defaults.set(defaultWidthIndex, forKey: "defaultWidthIndex") } }
    /// 켜면 도구 막대에서 바꾼 색과 굵기가 다음 기본값이 된다.
    @Published var rememberLastStyle: Bool { didSet { defaults.set(rememberLastStyle, forKey: "rememberLastStyle") } }
    @Published var captureTool: Tool { didSet { defaults.set(captureTool.key, forKey: "captureTool") } }
    @Published var whiteboardTool: Tool { didSet { defaults.set(whiteboardTool.key, forKey: "whiteboardTool") } }

    /// 보관할 캡처 개수(고정한 캡처는 빼고 센다). 0이면 무제한.
    @Published var keepCount: Int { didSet { defaults.set(keepCount, forKey: "keepCount"); CaptureStore.shared.prune() } }
    static let keepCountOptions = [50, 100, 200, 500, 0]
    @Published var captureSound: Bool { didSet { defaults.set(captureSound, forKey: "captureSound") } }
    @Published var boardStyle: BoardStyle { didSet { defaults.set(boardStyle.rawValue, forKey: "boardStyle") } }

    @Published var beautifyBackground: Beautifier.Background {
        didSet { defaults.set(beautifyBackground.rawValue, forKey: "beautifyBackground") }
    }
    /// `Beautifier.paddings`의 번호
    @Published var beautifyPadding: Int { didSet { defaults.set(beautifyPadding, forKey: "beautifyPadding") } }

    /// 타이머 캡처 단축키를 눌렀을 때 기다리는 시간(초).
    @Published var timerSeconds: Int { didSet { defaults.set(timerSeconds, forKey: "timerSeconds") } }
    static let timerOptions = [3, 5, 10]
    @Published var toolbarLayout: ToolbarLayout { didSet { defaults.set(toolbarLayout.rawValue, forKey: "toolbarLayout") } }
    @Published var toolbarAlignment: ToolbarAlignment { didSet { defaults.set(toolbarAlignment.rawValue, forKey: "toolbarAlignment") } }
    @Published var toolbarHint: Bool { didSet { defaults.set(toolbarHint, forKey: "toolbarHint") } }

    /// 팔레트. 항목은 "system:번호"(시스템 색) 또는 "#RRGGBB".
    @Published var paletteEntries: [String] {
        didSet {
            defaults.set(paletteEntries, forKey: "palette")
            if !palette.indices.contains(defaultColorIndex) { defaultColorIndex = 0 }
            NotificationCenter.default.post(name: Self.paletteDidChange, object: nil)
        }
    }
    static let paletteDidChange = Notification.Name("GrabbyPaletteDidChange")
    static let defaultPalette = AnnotationCanvas.systemColors.indices.map { "system:\($0)" }
    static let paletteLimit = 12

    var palette: [NSColor] { paletteEntries.compactMap(Self.color(from:)) }
    var defaultColor: NSColor { palette.indices.contains(defaultColorIndex) ? palette[defaultColorIndex] : (palette.first ?? .systemRed) }

    static func color(from entry: String) -> NSColor? {
        if entry.hasPrefix("system:"), let i = Int(entry.dropFirst(7)), AnnotationCanvas.systemColors.indices.contains(i) {
            return AnnotationCanvas.systemColors[i]
        }
        guard entry.hasPrefix("#"), entry.count == 7, let v = UInt32(entry.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }

    /// 팔레트 끝에 색을 더한다. 이미 있는 색이거나 꽉 찼으면 false.
    @discardableResult
    func addPaletteColor(_ color: NSColor) -> Bool {
        let entry = Self.hex(color)
        guard paletteEntries.count < Self.paletteLimit,
              !palette.contains(where: { Self.hex($0) == entry }) else { return false }
        paletteEntries.append(entry)
        return true
    }

    /// 색을 뺀다. 마지막 한 색은 남긴다.
    func removePaletteColor(at index: Int) {
        guard paletteEntries.count > 1, paletteEntries.indices.contains(index) else { return }
        paletteEntries.remove(at: index)
        if defaultColorIndex >= index, defaultColorIndex > 0 { defaultColorIndex -= 1 }
    }

    static let defaultSaveFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]

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
        // 화이트보드 기본값을 ⌃⌘3에서 ⌃⌘₩로 바꿨다. 예전 기본값 그대로면 새 기본값으로 옮긴다.
        let whiteboard = HotKeyAction.whiteboard.rawValue
        if saved[whiteboard] == KeyCombo.oldWhiteboardDefault { saved[whiteboard] = KeyCombo.defaults[whiteboard] }
        hotKeys = saved
        defaults.set(Array(known), forKey: knownActionsKey)

        language = Localization.language
        theme = defaults.string(forKey: "theme").flatMap(Theme.init) ?? .system
        confirmDelete = !defaults.bool(forKey: "skipDeleteConfirmation")
        // 예전 버전은 마지막으로 저장한 폴더를 기억했다. 있으면 기본 폴더로 이어받는다.
        let folder = defaults.string(forKey: "saveFolder") ?? defaults.string(forKey: "lastSaveFolder")
        saveFolder = folder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultSaveFolder
        saveFormat = defaults.string(forKey: "saveFormat").flatMap(SaveFormat.init) ?? .png
        saveWithoutPanel = defaults.bool(forKey: "saveWithoutPanel")

        let savedPalette = (defaults.stringArray(forKey: "palette") ?? Self.defaultPalette).filter { Self.color(from: $0) != nil }
        let entries = savedPalette.isEmpty ? Self.defaultPalette : savedPalette
        paletteEntries = entries
        let colorIndex = defaults.object(forKey: "defaultColorIndex") as? Int ?? 0
        defaultColorIndex = entries.indices.contains(colorIndex) ? colorIndex : 0
        let widthIndex = defaults.object(forKey: "defaultWidthIndex") as? Int ?? 1
        defaultWidthIndex = AnnotationCanvas.lineWidths.indices.contains(widthIndex) ? widthIndex : 1
        rememberLastStyle = defaults.bool(forKey: "rememberLastStyle")
        captureTool = defaults.string(forKey: "captureTool").flatMap(Tool.init(key:)) ?? .select
        whiteboardTool = defaults.string(forKey: "whiteboardTool").flatMap(Tool.init(key:)) ?? .pen
        keepCount = defaults.object(forKey: "keepCount") as? Int ?? 100
        captureSound = defaults.object(forKey: "captureSound") as? Bool ?? true
        boardStyle = defaults.string(forKey: "boardStyle").flatMap(BoardStyle.init) ?? .white
        beautifyBackground = defaults.string(forKey: "beautifyBackground").flatMap(Beautifier.Background.init) ?? .ocean
        beautifyPadding = defaults.object(forKey: "beautifyPadding") as? Int ?? 1
        timerSeconds = defaults.object(forKey: "timerSeconds") as? Int ?? 3
        toolbarLayout = defaults.string(forKey: "toolbarLayout").flatMap(ToolbarLayout.init) ?? .twoRows
        toolbarAlignment = defaults.string(forKey: "toolbarAlignment").flatMap(ToolbarAlignment.init) ?? .center
        toolbarHint = defaults.object(forKey: "toolbarHint") as? Bool ?? true
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    init() {
        NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.window?.title = L("Grabby 설정")
        }
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: .shared))
            // 언어를 바꿔 내용 크기가 달라지면 창 크기도 따라간다.
            controller.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: controller)
            w.styleMask = [.titled, .closable]
            w.title = L("Grabby 설정")
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    enum Tab: CaseIterable {
        case general, editing, saving, shortcuts, about

        var title: String {
            switch self {
            case .general: return L("일반")
            case .editing: return L("편집")
            case .saving: return L("저장")
            case .shortcuts: return L("단축키")
            case .about: return L("정보")
            }
        }
    }

    @ObservedObject var settings: AppSettings
    @State private var tab: Tab = .general
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("설정"), selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            // 분할 버튼은 글자가 바뀌어도 다시 그리지 않아서, 언어를 바꾸면 새로 만든다.
            .id("segment1-\(settings.language.rawValue)")
            .padding(.top, 12)

            switch tab {
            case .general: general
            case .editing: editing
            case .saving: saving
            case .shortcuts: shortcuts
            case .about: about
            }
        }
        .frame(width: 460)
        .fixedSize()
    }

    private var general: some View {
        Form {
            Section {
                Picker(L("언어"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(L("테마"), selection: $settings.theme) {
                    ForEach(AppSettings.Theme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                // 분할 버튼은 글자가 바뀌어도 다시 그리지 않아서, 언어를 바꾸면 새로 만든다.
                .id("segment2-\(settings.language.rawValue)")
                Toggle(L("로그인 시 실행"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle(L("탭을 삭제하기 전에 확인"), isOn: $settings.confirmDelete)
                Picker(L("보관할 캡처 수"), selection: $settings.keepCount) {
                    ForEach(AppSettings.keepCountOptions, id: \.self) { count in
                        Text(count == 0 ? L("무제한") : L("%ld개", count)).tag(count)
                    }
                }
                Text(L("고정(★)한 캡처는 개수에 넣지 않고 지우지 않아요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(L("캡처할 때 소리"), isOn: $settings.captureSound)
                Picker(L("타이머 캡처 시간"), selection: $settings.timerSeconds) {
                    ForEach(AppSettings.timerOptions, id: \.self) { Text(L("%ld초", $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .id("segment8-\(settings.language.rawValue)")
            }
        }
        .formStyle(.grouped)
    }

    private var editing: some View {
        Form {
            Section {
                PaletteEditor(settings: settings)
                Picker(L("기본 선 굵기"), selection: $settings.defaultWidthIndex) {
                    Text(L("얇게")).tag(0)
                    Text(L("보통")).tag(1)
                    Text(L("굵게")).tag(2)
                }
                .pickerStyle(.segmented)
                .id("segment3-\(settings.language.rawValue)")
                Toggle(L("마지막에 쓴 색과 굵기를 기본값으로 기억"), isOn: $settings.rememberLastStyle)
                Picker(L("캡처 도구 막대"), selection: $settings.toolbarLayout) {
                    ForEach(AppSettings.ToolbarLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .id("segment6-\(settings.language.rawValue)")
                Picker(L("도구 막대 위치"), selection: $settings.toolbarAlignment) {
                    ForEach(AppSettings.ToolbarAlignment.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .id("segment7-\(settings.language.rawValue)")
                Toggle(L("도구 막대 아래 안내 문구 보이기"), isOn: $settings.toolbarHint)
                Picker(L("캡처할 때 시작 도구"), selection: $settings.captureTool) {
                    ForEach(Tool.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Picker(L("꾸미기 배경"), selection: $settings.beautifyBackground) {
                    ForEach(Beautifier.Background.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(L("꾸미기 여백"), selection: $settings.beautifyPadding) {
                    Text(L("좁게")).tag(0)
                    Text(L("보통")).tag(1)
                    Text(L("넓게")).tag(2)
                }
                .pickerStyle(.segmented)
                .id("segment4-\(settings.language.rawValue)")
                Picker(L("화이트보드 바탕"), selection: $settings.boardStyle) {
                    ForEach(AppSettings.BoardStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .id("segment5-\(settings.language.rawValue)")
                Picker(L("화이트보드 시작 도구"), selection: $settings.whiteboardTool) {
                    ForEach(Tool.allCases.filter { $0 != .select }, id: \.self) { Text($0.name).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var saving: some View {
        Form {
            Section {
                LabeledContent(L("기본 저장 폴더")) {
                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([settings.saveFolder])
                        } label: {
                            Label(settings.saveFolder.lastPathComponent, systemImage: "folder")
                        }
                        .buttonStyle(.link)
                        .help(settings.saveFolder.path)
                        Button(L("변경…"), action: chooseFolder)
                    }
                }
                Picker(L("형식"), selection: $settings.saveFormat) {
                    ForEach(AppSettings.SaveFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(L("저장 창 없이 기본 폴더에 바로 저장"), isOn: $settings.saveWithoutPanel)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section {
                HotKeyEditor(settings: settings)
            }
        }
        .formStyle(.grouped)
    }


    private var about: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        let captures = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Grabby/Captures", isDirectory: true)
        return VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Grabby").font(.title.bold())
            Text(L("버전 %@ (%@)", version, build)).foregroundStyle(.secondary)
            Text(L("필요한 기능만 담은 메뉴바 화면 캡처 앱")).font(.callout)
            HStack {
                Button(L("캡처 폴더 열기")) { NSWorkspace.shared.open(captures) }
                Button(L("시작 안내")) { NSApp.sendAction(Selector(("openWelcome")), to: nil, from: nil) }
                Link(L("GitHub 저장소"), destination: URL(string: "https://github.com/eddieee-git/Grabby")!)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveFolder
        panel.prompt = L("폴더 선택")
        if panel.runModal() == .OK, let url = panel.url { settings.saveFolder = url }
    }
}

/// 편집 색 팔레트에서 하나를 고른다.
/// 팔레트 편집: 색을 누르면 기본 색, 오른쪽 클릭으로 빼기, 색을 골라 더하기, 기본값으로 되돌리기.
private struct PaletteEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var newColor = Color(nsColor: NSColor(srgbRed: 0.953, green: 0.502, blue: 0.125, alpha: 1))
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(L("팔레트 · 기본 색")) {
                ColorSwatches(selection: $settings.defaultColorIndex, settings: settings)
            }
            HStack(spacing: 8) {
                ColorPicker(L("새 색"), selection: $newColor, supportsOpacity: false)
                    .labelsHidden()
                Button(L("팔레트에 더하기")) {
                    let added = settings.addPaletteColor(NSColor(newColor))
                    message = added ? nil : (settings.paletteEntries.count >= AppSettings.paletteLimit
                                             ? L("팔레트는 %ld색까지예요.", AppSettings.paletteLimit) : L("이미 있는 색이에요."))
                }
                Button(L("기본 색 빼기")) { settings.removePaletteColor(at: settings.defaultColorIndex) }
                    .disabled(settings.paletteEntries.count <= 1)
                Spacer()
                Button(L("기본값으로")) { settings.paletteEntries = AppSettings.defaultPalette; settings.defaultColorIndex = 0 }
            }
            Text(message ?? L("색을 누르면 기본 색이 되고, 오른쪽 클릭으로 뺄 수 있어요. 최대 %ld색.", AppSettings.paletteLimit))
                .font(.caption)
                .foregroundStyle(message == nil ? Color.secondary : Color.orange)
        }
    }
}

private struct ColorSwatches: View {
    @Binding var selection: Int
    @ObservedObject var settings: AppSettings

    var body: some View {
        let palette = settings.palette
        HStack(spacing: 6) {
            ForEach(palette.indices, id: \.self) { index in
                Circle()
                    .fill(Color(nsColor: palette[index]))
                    .overlay(Circle().stroke(Color.gray.opacity(0.6), lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2).opacity(selection == index ? 1 : 0))
                    .contentShape(Circle())
                    .onTapGesture { selection = index }
                    .help(AppSettings.hex(palette[index]))
                    .contextMenu {
                        Button(L("빼기")) { settings.removePaletteColor(at: index) }
                            .disabled(palette.count <= 1)
                    }
            }
        }
    }
}

/// 전역 단축키를 입력받는다. 버튼을 누른 다음 원하는 조합을 누르면 저장한다.
private struct HotKeyEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var recording: HotKeyAction?
    @State private var monitor: Any?
    @State private var message: String?
    @State private var runningApps = HotKeyConflicts.runningCaptureApps
    @State private var blocked: [String] = []

    var body: some View {
        if !blocked.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("%@는 macOS 스크린샷 단축키와 겹쳐서 지금은 macOS가 먼저 받아요. 시스템 설정 > 키보드 > 키보드 단축키 > 스크린샷에서 그 항목을 꺼 주세요.",
                        blocked.joined(separator: ", ")), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(L("키보드 단축키 설정 열기")) { HotKeyConflicts.openSystemShortcutSettings() }
            }
        }
        if !runningApps.isEmpty {
            Label(L("%@이(가) 켜져 있어요. 같은 단축키를 쓰면 먼저 등록한 앱이 키를 받으니, 겹치지 않게 바꿔 주세요.",
                    runningApps.joined(separator: ", ")), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        ForEach(HotKeyAction.allCases, id: \.self) { action in
            LabeledContent(action.title) {
                HStack(spacing: 8) {
                    if settings.failedHotKeys.contains(action) {
                        Text(L("등록하지 못함")).font(.caption).foregroundStyle(.red)
                    }
                    Button(recording == action ? L("키를 누르세요") : settings.hotKeys[action.rawValue]?.displayText ?? L("없음")) {
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
                    .help(L("단축키 지우기"))
                }
            }
        }
        HStack {
            Text(message ?? L("다른 캡처 앱과 겹치면 먼저 등록한 앱이 키를 받아요. Esc로 입력 취소."))
                .font(.caption)
                .foregroundStyle(message == nil ? Color.secondary : Color.red)
            Spacer()
            Button(L("기본값으로")) {
                stop()
                settings.hotKeys = KeyCombo.defaults
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            runningApps = HotKeyConflicts.runningCaptureApps
            blocked = HotKeyConflicts.blockedBySystem(settings.hotKeys)
        }
        .onAppear { blocked = HotKeyConflicts.blockedBySystem(settings.hotKeys) }
        .onChange(of: settings.hotKeys) { _, combos in blocked = HotKeyConflicts.blockedBySystem(combos) }
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
            message = L("⌘, ⌃, ⌥ 중 하나와 함께 누르세요.")
            return
        }

        if let other = HotKeyAction.allCases.first(where: { $0 != action && settings.hotKeys[$0.rawValue] == combo }) {
            message = L("%@에서 쓰는 단축키예요.", other.title)
            return
        }
        settings.hotKeys[action.rawValue] = combo
        stop()
    }
}
