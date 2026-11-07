import AppKit

/// 도구, 색, 되돌리기와 호출한 쪽이 넘긴 버튼을 한 줄로 보여 주는 막대.
final class EditToolbar: NSVisualEffectView {
    struct Action {
        let symbol: String
        let title: String
        /// 있으면 아이콘 옆에 글자를 함께 보여 준다.
        var label: String? = nil
        /// 강조 색으로 눈에 띄게 보여 준다(완료 버튼).
        var isPrimary = false
        let handler: () -> Void
    }

    private let canvas: AnnotationCanvas
    private let tools: NSSegmentedControl
    private let colors: NSSegmentedControl
    private let widths: NSSegmentedControl
    private var actions: [Action] = []
    /// 막대에 보여 줄 도구(순서대로).
    private let toolList: [Tool]

    /// `hint`가 있으면 버튼 줄 아래에 작은 안내 문구를 보여 준다.
    init(canvas: AnnotationCanvas, tools toolList: [Tool], actions: [Action], hint: String? = nil) {
        self.canvas = canvas
        self.actions = actions
        self.toolList = toolList
        tools = NSSegmentedControl(images: toolList.map { Self.symbol($0.symbol, $0.title) },
                                   trackingMode: .selectOne, target: nil, action: nil)
        colors = NSSegmentedControl(images: AnnotationCanvas.palette.map(Self.swatch), trackingMode: .selectOne, target: nil, action: nil)
        widths = NSSegmentedControl(images: AnnotationCanvas.lineWidths.map(Self.lineSample), trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: .zero)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        for (index, tool) in toolList.enumerated() { tools.setToolTip(tool.title, forSegment: index) }
        tools.target = self
        tools.action = #selector(toolChanged)
        colors.target = self
        colors.action = #selector(colorChanged)
        widths.target = self
        widths.action = #selector(widthChanged)
        for (index, title) in [L("얇게"), L("보통"), L("굵게")].enumerated() { widths.setToolTip(L("선 굵기·글자 크기: %@", title), forSegment: index) }

        let undo = button(symbol: "arrow.uturn.backward", title: L("되돌리기 (⌘Z)"), action: #selector(undoTapped))
        let redo = button(symbol: "arrow.uturn.forward", title: L("다시 실행 (⇧⌘Z)"), action: #selector(redoTapped))
        var views: [NSView] = [tools, colors, widths, undo, redo]
        for (index, action) in actions.enumerated() {
            let b = button(symbol: action.symbol, title: action.title, action: #selector(actionTapped(_:)))
            b.tag = index
            if let label = action.label {
                b.title = label
                b.imagePosition = .imageLeading
            }
            if action.isPrimary {
                b.bezelStyle = .push
                b.bezelColor = .controlAccentColor
                b.contentTintColor = .white
                b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                    .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                ])
            }
            views.append(b)
        }
        let row = NSStackView(views: views)
        row.spacing = 8
        row.setCustomSpacing(4, after: colors)
        var rows: [NSView] = [row]
        if let hint {
            let label = NSTextField(labelWithString: hint)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            rows.append(label)
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
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
        tools.selectedSegment = toolList.firstIndex(of: canvas.tool) ?? -1
        colors.selectedSegment = AnnotationCanvas.palette.firstIndex(of: canvas.color) ?? 0
        widths.selectedSegment = canvas.widthLevel
    }

    private func button(symbol: String, title: String, action: Selector) -> NSButton {
        let b = NSButton(image: Self.symbol(symbol, title), target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.toolTip = title
        return b
    }

    @objc private func toolChanged() {
        if toolList.indices.contains(tools.selectedSegment) { canvas.tool = toolList[tools.selectedSegment] }
        canvas.window?.invalidateCursorRects(for: canvas)
    }

    @objc private func colorChanged() {
        let index = max(0, colors.selectedSegment)
        canvas.applyColor(index)
        let settings = AppSettings.shared
        if settings.rememberLastStyle { settings.defaultColorIndex = index }
    }

    @objc private func widthChanged() {
        let index = max(0, widths.selectedSegment)
        canvas.applyWidthLevel(index)
        let settings = AppSettings.shared
        if settings.rememberLastStyle { settings.defaultWidthIndex = index }
    }

    @objc private func undoTapped() { canvas.undo() }
    @objc private func redoTapped() { canvas.redo() }

    @objc private func actionTapped(_ sender: NSButton) { actions[sender.tag].handler() }

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }

    /// 굵기를 보여 주는 가로선 아이콘.
    private static func lineSample(_ width: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { rect in
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 2, y: rect.midY))
            line.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY))
            line.lineWidth = min(width, 6) * 0.9
            line.lineCapStyle = .round
            NSColor.black.setStroke()
            line.stroke()
            return true
        }
        image.isTemplate = true
        return image
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
