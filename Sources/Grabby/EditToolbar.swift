import AppKit

/// 도구, 색, 되돌리기와 호출한 쪽이 넘긴 버튼을 한 줄로 보여 주는 막대.
final class EditToolbar: NSVisualEffectView {
    struct Action {
        let symbol: String
        let title: String
        let handler: () -> Void
    }

    private let canvas: AnnotationCanvas
    private let tools: NSSegmentedControl
    private let colors: NSSegmentedControl
    private var actions: [Action] = []

    init(canvas: AnnotationCanvas, actions: [Action]) {
        self.canvas = canvas
        self.actions = actions
        tools = NSSegmentedControl(images: Tool.allCases.map { Self.symbol($0.symbol, $0.title) },
                                   trackingMode: .selectOne, target: nil, action: nil)
        colors = NSSegmentedControl(images: AnnotationCanvas.palette.map(Self.swatch), trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: .zero)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        for tool in Tool.allCases { tools.setToolTip(tool.title, forSegment: tool.rawValue) }
        tools.target = self
        tools.action = #selector(toolChanged)
        colors.target = self
        colors.action = #selector(colorChanged)

        let undo = button(symbol: "arrow.uturn.backward", title: "되돌리기 (⌘Z)", action: #selector(undoTapped))
        var views: [NSView] = [tools, colors, undo]
        for (index, action) in actions.enumerated() {
            let b = button(symbol: action.symbol, title: action.title, action: #selector(actionTapped(_:)))
            b.tag = index
            views.append(b)
        }
        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.setCustomSpacing(4, after: colors)
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        canvas.onToolChange = { [weak self] in self?.sync() }
        sync()
        setFrameSize(fittingSize)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func sync() {
        tools.selectedSegment = canvas.tool.rawValue
        colors.selectedSegment = AnnotationCanvas.palette.firstIndex(of: canvas.color) ?? 0
    }

    private func button(symbol: String, title: String, action: Selector) -> NSButton {
        let b = NSButton(image: Self.symbol(symbol, title), target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.toolTip = title
        return b
    }

    @objc private func toolChanged() {
        if let tool = Tool(rawValue: tools.selectedSegment) { canvas.tool = tool }
        canvas.window?.invalidateCursorRects(for: canvas)
    }

    @objc private func colorChanged() {
        canvas.color = AnnotationCanvas.palette[max(0, colors.selectedSegment)]
    }

    @objc private func undoTapped() { canvas.undo() }

    @objc private func actionTapped(_ sender: NSButton) { actions[sender.tag].handler() }

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill()
            circle.fill()
            NSColor.gray.withAlphaComponent(0.6).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
