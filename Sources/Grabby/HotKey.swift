import AppKit
import Carbon

/// Carbon RegisterEventHotKey 기반 전역 단축키. 손쉬운 사용 권한이 필요 없다.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void

    /// 시스템이 등록을 거부하면 nil.
    init?(id: UInt32, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.id = id
        self.action = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x4752_4259), id: id) // 'GRBY'
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
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
