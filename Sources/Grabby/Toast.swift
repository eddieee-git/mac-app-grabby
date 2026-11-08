import AppKit

/// 화면 아래쪽에 잠깐 떴다 사라지는 알림. 다른 앱의 포커스를 빼앗지 않는다.
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    /// 바로 치운다(타이머 캡처에서 알림이 찍히지 않게).
    static func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    static func show(_ message: String, image: NSImage? = nil) {
        panel?.orderOut(nil)
        hideWork?.cancel()

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        var views: [NSView] = []
        if let image {
            let thumb = NSImageView(image: image)
            thumb.imageScaling = .scaleProportionallyDown
            thumb.translatesAutoresizingMaskIntoConstraints = false
            thumb.widthAnchor.constraint(equalToConstant: 56).isActive = true
            thumb.heightAnchor.constraint(equalToConstant: 36).isActive = true
            views.append(thumb)
        }
        views.append(label)
        let stack = NSStackView(views: views)
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 16)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        let size = stack.fittingSize

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + 80, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = background
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
                panel.orderOut(nil)
                if Toast.panel === panel { Toast.panel = nil }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}
