import AppKit

/// 캡처를 화면 위에 띄워 두는 작은 창. 끌어서 옮기고, 두 손가락 오므리기나 ⌘+스크롤로 크기를 바꾸고,
/// 더블클릭이나 Esc로 닫는다. 오른쪽 클릭 메뉴에서 복사·저장·투명도를 고른다.
final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []

    private let image: CGImage
    private let scale: CGFloat
    private let imageView = PinImageView()
    private var zoom: CGFloat = 1

    /// `frame`은 전역 좌표(왼쪽 아래 원점). 캡처한 자리에 그대로 띄우면 화면에 붙어 있는 것처럼 보인다.
    static func show(_ image: CGImage, scale: CGFloat, at frame: CGRect) {
        let pin = PinWindow(image: image, scale: scale, frame: frame)
        open.append(pin)
        pin.orderFrontRegardless()
    }

    static func closeAll() {
        for pin in open { pin.close() }
    }

    private init(image: CGImage, scale: CGFloat, frame: CGRect) {
        self.image = image
        self.scale = scale
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        imageView.image = NSImage(cgImage: image, size: frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
        imageView.pin = self
        imageView.menu = makeMenu()
        contentView = imageView
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        Self.open.removeAll { $0 === self }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods == .command else { return super.performKeyEquivalent(with: event) }
        switch event.keyCode {
        case 8: copyImage() // C
        case 13: close() // W
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// 왼쪽 위를 고정한 채 크기를 바꾼다.
    fileprivate func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.2), 5)
        let base = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let size = CGSize(width: (base.width * zoom).rounded(), height: (base.height * zoom).rounded())
        var rect = frame
        rect.origin.y = frame.maxY - size.height
        rect.size = size
        setFrame(rect, display: true)
    }

    fileprivate func zoom(by factor: CGFloat) { setZoom(zoom * factor) }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(L("복사"), #selector(copyImage)))
        menu.addItem(item(L("저장…"), #selector(saveImage)))
        menu.addItem(.separator())
        menu.addItem(item(L("실제 크기"), #selector(actualSize)))
        let opacity = NSMenuItem(title: L("투명도"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for value in [100, 80, 60, 40] {
            let entry = item("\(value)%", #selector(setOpacity(_:)))
            entry.tag = value
            sub.addItem(entry)
        }
        opacity.submenu = sub
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(item(L("닫기"), #selector(closePin)))
        menu.addItem(item(L("띄운 캡처 모두 닫기"), #selector(closeAllPins)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func copyImage() {
        Clipboard.copy(image, scale: scale)
        Toast.show(L("복사했어요"))
    }

    @objc private func saveImage() { ImageSaver.save(image, scale: scale) }
    @objc private func actualSize() { setZoom(1) }
    @objc private func setOpacity(_ sender: NSMenuItem) { alphaValue = CGFloat(sender.tag) / 100 }
    @objc private func closePin() { close() }
    @objc private func closeAllPins() { Self.closeAll() }
}

private final class PinImageView: NSImageView {
    weak var pin: PinWindow?

    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { pin?.close(); return }
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func magnify(with event: NSEvent) { pin?.zoom(by: 1 + event.magnification) }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return super.scrollWheel(with: event) }
        pin?.zoom(by: event.scrollingDeltaY > 0 ? 1.05 : 0.95)
    }
}
