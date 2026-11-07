import AppKit
import Carbon

/// 전역 단축키로 실행할 수 있는 동작.
enum HotKeyAction: String, CaseIterable {
    case captureArea, repeatLastArea, whiteboard

    var title: String {
        switch self {
        case .captureArea: return "영역 캡처"
        case .repeatLastArea: return "마지막 영역 다시 캡처"
        case .whiteboard: return "화이트보드"
        }
    }
}

/// 키와 보조키 조합. `key`는 화면에 보여 줄 키 이름이다.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon 형식(cmdKey, optionKey 등)
    var modifiers: UInt32
    var key: String

    static let defaults: [String: KeyCombo] = {
        let controlCommand = UInt32(controlKey | cmdKey)
        return [
            HotKeyAction.captureArea.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: controlCommand, key: "1"),
            HotKeyAction.repeatLastArea.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: controlCommand, key: "2"),
            HotKeyAction.whiteboard.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: controlCommand, key: "3"),
        ]
    }()

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// 전역 단축키로 쓸 수 없는 입력이면 nil. 기능 키 말고는 ⌘, ⌃, ⌥ 중 하나가 있어야 한다.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }

        let code = Int(event.keyCode)
        guard let name = Self.specialKeys[code] ?? Self.asciiName(of: event.keyCode) else { return nil }
        let isFunctionKey = name.hasPrefix("F") && name.count > 1
        guard isFunctionKey || carbon & (cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.init(keyCode: UInt32(code), modifiers: UInt32(carbon), key: name)
    }

    /// 한글 입력 상태에서도 영문 키 이름을 얻으려고 ASCII 자판으로 변환한다.
    private static func asciiName(of keyCode: UInt16) -> String? {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode, UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    var displayText: String {
        let mods = Int(modifiers)
        return (mods & controlKey != 0 ? "⌃" : "") + (mods & optionKey != 0 ? "⌥" : "")
            + (mods & shiftKey != 0 ? "⇧" : "") + (mods & cmdKey != 0 ? "⌘" : "") + key
    }

    /// 메뉴 항목에 표시할 키. 특수 키는 메뉴에 그대로 쓸 수 없어 표시하지 않는다.
    var menuKey: String { Self.specialKeys[Int(keyCode)] == nil ? key.lowercased() : "" }

    var menuModifiers: NSEvent.ModifierFlags {
        let mods = Int(modifiers)
        var flags: NSEvent.ModifierFlags = []
        if mods & cmdKey != 0 { flags.insert(.command) }
        if mods & optionKey != 0 { flags.insert(.option) }
        if mods & controlKey != 0 { flags.insert(.control) }
        if mods & shiftKey != 0 { flags.insert(.shift) }
        return flags
    }
}

/// Carbon RegisterEventHotKey 기반 전역 단축키. 손쉬운 사용 권한이 필요 없다.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void

    /// 시스템이 등록을 거부하면 nil. 다른 앱과 겹치는 조합은 대부분 거부되지 않고 등록되며, 먼저 등록한 앱이 받는다.
    init?(id: UInt32, combo: KeyCombo, action: @escaping () -> Void) {
        self.id = id
        self.action = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x4752_4259), id: id) // 'GRBY'
        guard RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            return nil
        }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            // 단축키마다 처리기가 따로 있으므로 내 것이 아니면 다음 처리기로 넘긴다.
            guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            hotKey.action()
            return noErr
        }, 1, &spec, userData, &handlerRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
