import AppKit
import Carbon

/// 캔버스를 담는 스크롤 영역. 크기가 바뀔 때마다 캔버스 크기를 다시 맞춘다.
final class ZoomScrollView: NSScrollView {
    var onTile: (() -> Void)?

    override func tile() {
        super.tile()
        onTile?()
    }
}

/// 탭 창의 단축키를 받는다.
final class LibraryWindow: NSWindow {
    weak var library: LibraryWindowController?

    @objc func copy(_ sender: Any?) { library?.copyCurrent() }
    @objc func paste(_ sender: Any?) { library?.pasteImage() }
    @objc func saveDocument(_ sender: Any?) { library?.saveCurrent() }
    @objc func undo(_ sender: Any?) { library?.undoAnnotation() }
    @objc func redo(_ sender: Any?) { library?.redoAnnotation() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let library, mods.contains(.command), !library.isEditingText else { return super.performKeyEquivalent(with: event) }
        switch KeyLetter.of(event) {
        case "p" where mods == .command: library.pinCurrent()
        case "t" where mods == .command: library.recognizeCurrent()
        case "r" where mods == .command: library.readCodeCurrent()
        case "b" where mods == .command: library.beautifyCurrent()
        case "=": library.zoom { $0.zoomIn() }
        case "-": library.zoom { $0.zoomOut() }
        case "0" where mods == .command: library.zoom { $0.zoomToActualSize() }
        case "9" where mods == .command: library.zoom { $0.zoomToFit() }
        case "z" where mods == [.command, .shift]: library.redoAnnotation()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let library, !library.isEditingText,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete: library.deleteKey()
        case kVK_Escape: library.clearSelections()
        case kVK_LeftArrow: library.moveSelection(by: -1)
        case kVK_RightArrow: library.moveSelection(by: 1)
        default:
            if let tool = Tool.forLetter(KeyLetter.of(event)) { library.selectTool(tool) } else { super.keyDown(with: event) }
        }
    }
}
