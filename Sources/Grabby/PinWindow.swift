import AppKit

/// 캡처를 화면 위에 띄워 두는 작은 창. 끌어서 옮기고, 두 손가락 오므리기나 ⌘+스크롤로 크기를 바꾸고,
/// 더블클릭이나 Esc로 닫는다. 오른쪽 클릭 메뉴에서 복사·저장·투명도를 고른다.
final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []

    private let id: UUID
    private let image: CGImage
    private let scale: CGFloat
    private let imageView = PinImageView()
    private var zoom: CGFloat = 1

    /// 다시 켤 때 되살릴 수 있게 띄운 캡처를 ~/Library/Application Support/Grabby/Pins에 둔다.
    private struct Saved: Codable {
        let id: UUID
        let frame: CGRect
        let scale: CGFloat
        let zoom: CGFloat
        let alpha: CGFloat
    }

    private static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Grabby/Pins", isDirectory: true)
    private static var indexURL: URL { folder.appendingPathComponent("pins.json") }
    private static func imageURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).png") }

    /// `frame`은 전역 좌표(왼쪽 아래 원점). 캡처한 자리에 그대로 띄우면 화면에 붙어 있는 것처럼 보인다.
    static func show(_ image: CGImage, scale: CGFloat, at frame: CGRect) {
        let pin = PinWindow(id: UUID(), image: image, scale: scale, frame: frame)
        open.append(pin)
        pin.orderFrontRegardless()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = imageURL(pin.id)
        DispatchQueue.global(qos: .utility).async {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        saveAll()
    }

    static func closeAll() {
        for pin in open { pin.close() }
    }

    /// 띄운 캡처의 자리·크기·투명도를 저장한다(앱을 끝낼 때와 열고 닫을 때).
    static func saveAll() {
        let saved = open.map { Saved(id: $0.id, frame: $0.frame, scale: $0.scale, zoom: $0.zoom, alpha: $0.alphaValue) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: indexURL, options: .atomic) }
    }

    /// 지난번에 띄워 둔 캡처를 되살린다. 화면 밖으로 나간 것은 보이는 자리로 옮긴다.
    static func restore() {
        guard let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([Saved].self, from: data) else { return }
        for entry in saved {
            guard let source = CGImageSourceCreateWithURL(imageURL(entry.id) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            var frame = entry.frame
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }), let screen = NSScreen.main {
                frame.origin = CGPoint(x: screen.visibleFrame.midX - frame.width / 2, y: screen.visibleFrame.midY - frame.height / 2)
            }
            let pin = PinWindow(id: entry.id, image: image, scale: entry.scale, frame: frame)
            pin.zoom = entry.zoom
            pin.alphaValue = entry.alpha
            open.append(pin)
            pin.orderFrontRegardless()
        }
    }

    /// 핀을 다시 켤 때 되살리지 않으면 저장해 둔 것을 지운다.
    static func discardSaved() {
        try? FileManager.default.removeItem(at: folder)
    }

    private init(id: UUID, image: CGImage, scale: CGFloat, frame: CGRect) {
        self.id = id
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
        try? FileManager.default.removeItem(at: Self.imageURL(id))
        Self.saveAll()
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
