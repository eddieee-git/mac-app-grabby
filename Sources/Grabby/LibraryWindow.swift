import AppKit

/// 캡처 탭 창. 캡처할 때마다 오른쪽 끝에 탭이 하나씩 늘어나고, 고른 탭을 보고, 이어서 편집하고, 다시 복사한다.
final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    private let store = CaptureStore.shared
    private let canvas = AnnotationCanvas(image: LibraryWindowController.blank, pixelScale: 1)
    private let emptyLabel = NSTextField(labelWithString: "아직 캡처가 없어요.\n메뉴바의 영역 캡처나 단축키로 화면을 캡처해 보세요.")
    private let tabStrip = NSStackView()
    private let tabScroll = NSScrollView()
    private let pinButton = NSButton()
    private var tabs: [CaptureTab] = []
    private var selectedID: UUID?
    private var shownID: UUID?
    private var knownNewest: UUID?
    private var isPersisting = false

    private let pinKey = "libraryPinned"

    private static let blank: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    init() {
        let window = LibraryWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Grabby"
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        if !window.setFrameUsingName("CaptureTabs") { window.center() }
        window.setFrameAutosaveName("CaptureTabs")
        window.delegate = self
        window.library = self
        build()
        setPinned(UserDefaults.standard.bool(forKey: pinKey))
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: CaptureStore.didChange, object: nil)
        knownNewest = store.items.first?.id
        reloadTabs()
        select(store.items.first?.id)
    }

    required init?(coder: NSCoder) { fatalError() }

    var isVisible: Bool { window?.isVisible == true }

    /// 앱을 앞으로 가져와 창을 연다(메뉴에서 열 때).
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 다른 앱의 포커스는 그대로 두고 창만 앞에 띄운다(캡처 직후).
    func showWithoutFocus() {
        window?.orderFrontRegardless()
    }

    private func build() {
        guard let content = window?.contentView else { return }

        tabStrip.orientation = .horizontal
        tabStrip.spacing = 4
        tabStrip.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabScroll.documentView = tabStrip
        tabScroll.hasHorizontalScroller = true
        tabScroll.autohidesScrollers = true
        tabScroll.horizontalScrollElasticity = .allowed
        tabScroll.verticalScrollElasticity = .none
        tabScroll.drawsBackground = false
        let clip = tabScroll.contentView
        NSLayoutConstraint.activate([
            tabStrip.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            tabStrip.topAnchor.constraint(equalTo: clip.topAnchor),
            tabStrip.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
        ])

        pinButton.bezelStyle = .texturedRounded
        pinButton.setButtonType(.toggle)
        pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "항상 위에")
        pinButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "항상 위에")
        pinButton.toolTip = "창을 항상 위에 두기"
        pinButton.target = self
        pinButton.action = #selector(pinToggled)

        let header = NSView()
        let divider = NSBox()
        divider.boxType = .separator

        let toolbar = EditToolbar(canvas: canvas, actions: [
            .init(symbol: "doc.on.doc", title: "복사 (⌘C)") { [weak self] in self?.copyCurrent() },
            .init(symbol: "folder", title: "Finder에서 보기") { [weak self] in self?.revealCurrent() },
            .init(symbol: "trash", title: "삭제 (⌫)") { [weak self] in self?.deleteCurrent() },
        ])

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor

        for view in [header, tabScroll, pinButton, divider, toolbar, canvas, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        content.addSubview(header)
        header.addSubview(tabScroll)
        header.addSubview(pinButton)
        content.addSubview(divider)
        content.addSubview(toolbar)
        content.addSubview(canvas)
        content.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 56),

            tabScroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            tabScroll.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -6),
            tabScroll.topAnchor.constraint(equalTo: header.topAnchor, constant: 6),
            tabScroll.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -4),
            pinButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            pinButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            divider.topAnchor.constraint(equalTo: header.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            toolbar.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            toolbar.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            emptyLabel.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
        ])
    }

    // MARK: 탭

    /// 오래된 것이 왼쪽, 새 캡처가 오른쪽 끝에 오도록 탭을 다시 만든다.
    private func reloadTabs() {
        for tab in tabs { tab.removeFromSuperview() }
        tabs = store.items.reversed().map { item in
            let tab = CaptureTab(item: item, thumbnail: store.thumbnail(for: item), fileURL: store.url(for: item))
            tab.onSelect = { [weak self] in self?.select(item.id) }
            tab.onClose = { [weak self] in self?.delete(item.id) }
            tab.onDoubleClick = { [weak self] in self?.copyCurrent() }
            return tab
        }
        for tab in tabs { tabStrip.addArrangedSubview(tab) }
        updateSelection()
    }

    private func select(_ id: UUID?, reveal: Bool = true) {
        if id != selectedID { saveEdits() }
        selectedID = id.flatMap { id in store.items.contains { $0.id == id } ? id : nil }
        updateSelection()
        showSelected()
        if reveal, let tab = tabs.first(where: { $0.item.id == selectedID }) {
            tabStrip.layoutSubtreeIfNeeded()
            tab.scrollToVisible(tab.bounds)
        }
    }

    private func updateSelection() {
        for tab in tabs { tab.isSelected = tab.item.id == selectedID }
    }

    /// 왼쪽(-1)이나 오른쪽(+1) 탭으로 옮긴다.
    func moveSelection(by offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.item.id == selectedID }) else { return }
        let next = min(max(index + offset, 0), tabs.count - 1)
        select(tabs[next].item.id)
    }

    @objc private func storeChanged() {
        guard !isPersisting else { return }
        // 새 캡처가 들어오면 그 탭을 고른다. 그 밖의 변경은 보던 탭을 유지한다.
        let newest = store.items.first
        reloadTabs()
        if let newest, newest.id != knownNewest {
            knownNewest = newest.id
            select(newest.id)
        } else {
            select(selectedID ?? newest?.id)
        }
    }

    private var selectedItem: CaptureItem? { store.items.first { $0.id == selectedID } }

    private func showSelected() {
        guard let item = selectedItem, let image = store.image(for: item) else {
            shownID = nil
            canvas.setImage(Self.blank, pixelScale: 1)
            canvas.isHidden = true
            emptyLabel.isHidden = !store.items.isEmpty
            return
        }
        guard item.id != shownID else { return }
        shownID = item.id
        canvas.isHidden = false
        emptyLabel.isHidden = true
        canvas.setImage(image, pixelScale: item.scale)
    }

    /// 보던 캡처에 그린 표시를 이미지에 합쳐 저장한다.
    private func saveEdits() {
        guard let id = shownID, let item = store.items.first(where: { $0.id == id }), canvas.hasEdits else { return }
        persist(item, canvas.render())
    }

    /// 탭 순서는 그대로 두고 이미지만 바꾼다. 저장 알림으로 탭을 다시 만들지 않게 막는다.
    private func persist(_ item: CaptureItem, _ image: CGImage) {
        isPersisting = true
        store.replace(item, with: image)
        isPersisting = false
        tabs.first { $0.item.id == item.id }?.thumbnail = store.thumbnail(for: item)
    }

    // MARK: 동작

    func copyCurrent() {
        guard let item = selectedItem else { return }
        if canvas.hasEdits, item.id == shownID {
            let image = canvas.render()
            persist(item, image)
            canvas.setImage(image, pixelScale: item.scale)
        }
        guard let image = store.image(for: item) else { return }
        Clipboard.copy(image, scale: item.scale)
        Toast.show("복사했어요", image: store.thumbnail(for: item))
    }

    private func revealCurrent() {
        guard let item = selectedItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.url(for: item)])
    }

    func deleteCurrent() {
        if let selectedID { delete(selectedID) }
    }

    /// 탭을 지우고 오른쪽 탭(없으면 왼쪽 탭)을 고른다.
    private func delete(_ id: UUID) {
        guard let item = store.items.first(where: { $0.id == id }) else { return }
        let index = tabs.firstIndex { $0.item.id == id } ?? 0
        let wasSelected = id == selectedID
        if wasSelected {
            shownID = nil
            canvas.setImage(Self.blank, pixelScale: 1)
        }
        isPersisting = true
        store.remove(item)
        isPersisting = false
        knownNewest = store.items.first?.id
        reloadTabs()
        if wasSelected {
            let next = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].item.id
            select(next)
        } else {
            select(selectedID, reveal: false)
        }
    }

    @objc private func pinToggled() { setPinned(pinButton.state == .on) }

    private func setPinned(_ pinned: Bool) {
        pinButton.state = pinned ? .on : .off
        pinButton.contentTintColor = pinned ? .controlAccentColor : nil
        window?.level = pinned ? .floating : .normal
        UserDefaults.standard.set(pinned, forKey: pinKey)
    }

    func undoAnnotation() { canvas.undo() }

    var isEditingText: Bool { canvas.isEditingText }

    func selectTool(_ tool: Tool) { canvas.tool = tool; window?.invalidateCursorRects(for: canvas) }

    func windowWillClose(_ notification: Notification) { saveEdits() }
}

/// 탭 창의 단축키(⌘C, ⌘Z, ⌫, ←/→, 도구 글자)를 받는다.
final class LibraryWindow: NSWindow {
    weak var library: LibraryWindowController?

    @objc func copy(_ sender: Any?) { library?.copyCurrent() }
    @objc func undo(_ sender: Any?) { library?.undoAnnotation() }

    override func keyDown(with event: NSEvent) {
        guard let library, !library.isEditingText,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51, 117: library.deleteCurrent() // ⌫, ⌦
        case 123: library.moveSelection(by: -1) // ←
        case 124: library.moveSelection(by: 1) // →
        default:
            if let tool = Tool.forKeyCode(event.keyCode) { library.selectTool(tool) } else { super.keyDown(with: event) }
        }
    }
}

/// 썸네일, 시각, 닫기 버튼이 있는 탭 하나. 다른 앱으로 끌어다 놓으면 이미지 파일이 넘어간다.
final class CaptureTab: NSView, NSDraggingSource {
    let item: CaptureItem
    private let fileURL: URL
    private let imageView = NSImageView()
    private let label: NSTextField
    private let closeButton = NSButton()
    private var mouseDownPoint: CGPoint?

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    var thumbnail: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    var isSelected = false {
        didSet {
            layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
                                                : NSColor.labelColor.withAlphaComponent(0.05).cgColor
            label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "a h:mm:ss"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d a h:mm"
        return f
    }()

    init(item: CaptureItem, thumbnail: NSImage?, fileURL: URL) {
        self.item = item
        self.fileURL = fileURL
        let formatter = Calendar.current.isDateInToday(item.date) ? Self.timeFormatter : Self.dayFormatter
        label = NSTextField(labelWithString: formatter.string(from: item.date))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = "\(item.width)×\(item.height)"

        imageView.image = thumbnail
        imageView.imageScaling = .scaleProportionallyDown
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "닫기")
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "삭제"
        closeButton.target = self
        closeButton.action = #selector(closeTapped)

        for view in [imageView, label, closeButton] {
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
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -2),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14),
        ])
        isSelected = false
    }

    required init?(coder: NSCoder) { fatalError() }

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
