import AppKit

/// 타이머 캡처가 몇 초 남았는지 마우스가 있는 화면 가운데에 크게 보여 준다.
/// 클릭을 받지 않고 포커스도 가져가지 않는다. 캡처 전에 치워서 찍히지 않게 한다.
@MainActor
enum Countdown {
    private static var panel: NSPanel?
    private static var number: NSTextField?

    static func show(_ seconds: Int) {
        if panel == nil { build() }
        number?.stringValue = "\(seconds)"
        if let panel, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        }
        panel?.orderFrontRegardless()
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
        number = nil
    }

    private static func build() {
        let size = NSSize(width: 200, height: 180)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 24
        background.layer?.masksToBounds = true

        let digits = NSTextField(labelWithString: "")
        digits.font = .monospacedDigitSystemFont(ofSize: 96, weight: .semibold)
        digits.alignment = .center
        let caption = NSTextField(labelWithString: L("단축키를 다시 누르면 취소"))
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        let stack = NSStackView(views: [digits, caption])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        p.contentView = background
        p.setAccessibilityLabel(L("타이머 캡처"))
        panel = p
        number = digits
    }
}
