import AppKit

/// 썸네일, 시각, 닫기 버튼이 있는 탭 하나. 다른 앱으로 끌어다 놓으면 이미지 파일이 넘어간다.
final class CaptureTab: NSView, NSDraggingSource {
    let item: CaptureItem
    private let fileURL: URL
    private let imageView = NSImageView()
    private let label: NSTextField
    private let star = NSImageView()
    private let closeButton = NSButton()
    private var mouseDownPoint: CGPoint?

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    var thumbnail: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    var isSelected = false { didSet { applyColors() } }

    init(item: CaptureItem, thumbnail: NSImage?, fileURL: URL) {
        self.item = item
        self.fileURL = fileURL
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Localization.language == .korean ? "ko_KR" : "en_US")
        if Calendar.current.isDateInToday(item.date) {
            formatter.timeStyle = .medium
        } else {
            formatter.setLocalizedDateFormatFromTemplate("Mdjmm")
        }
        let time = formatter.string(from: item.date)
        label = NSTextField(labelWithString: item.note ?? time)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = [item.note, time, "\(item.width)×\(item.height)"].compactMap { $0 }.joined(separator: "\n")

        imageView.image = thumbnail
        imageView.imageScaling = .scaleProportionallyDown
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        star.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: L("고정"))
        star.contentTintColor = .systemYellow
        star.isHidden = !item.isKept
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("닫기"))
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = L("삭제")
        closeButton.target = self
        closeButton.action = #selector(closeTapped)

        for view in [imageView, label, star, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 156),
            heightAnchor.constraint(equalToConstant: 42),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 32),
            star.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: -2),
            star.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -3),
            star.widthAnchor.constraint(equalToConstant: 12),
            star.heightAnchor.constraint(equalToConstant: 12),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -2),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14),
        ])
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 레이어 색은 테마가 바뀌어도 저절로 바뀌지 않아서 다시 칠한다.
    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
                                                : NSColor.labelColor.withAlphaComponent(0.05).cgColor
        }
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func closeTapped() { onClose?() }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        if event.clickCount == 2 { onDoubleClick?() } else { onSelect?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        let dragItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        dragItem.setDraggingFrame(imageView.frame, contents: imageView.image)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
