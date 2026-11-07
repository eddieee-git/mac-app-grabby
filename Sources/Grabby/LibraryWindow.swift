import AppKit

/// 캡처 보관함. 왼쪽 썸네일 목록에서 고르면 오른쪽에서 보고, 이어서 편집하고, 다시 복사한다.
final class LibraryWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let store = CaptureStore.shared
    private let table = NSTableView()
    private let canvas = AnnotationCanvas(image: LibraryWindowController.blank, pixelScale: 1)
    private let emptyLabel = NSTextField(labelWithString: "아직 캡처가 없어요.\n⌃⌘1로 화면을 캡처해 보세요.")
    private var shown: CaptureItem?
    private var knownNewest: UUID?
    private var isPersisting = false

    private static let blank: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 a h:mm"
        return f
    }()

    init() {
        let window = LibraryWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Grabby 보관함"
        window.minSize = NSSize(width: 600, height: 400)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Library")
        super.init(window: window)
        window.delegate = self
        window.library = self
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: CaptureStore.didChange, object: nil)
        knownNewest = store.items.first?.id
        reload(select: store.items.first)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        guard let content = window?.contentView else { return }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("capture"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 132
        table.style = .sourceList
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(copyCurrent)
        table.target = self
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let toolbar = EditToolbar(canvas: canvas, actions: [
            .init(symbol: "doc.on.doc", title: "복사 (⌘C)") { [weak self] in self?.copyCurrent() },
            .init(symbol: "folder", title: "Finder에서 보기") { [weak self] in self?.revealCurrent() },
            .init(symbol: "trash", title: "삭제 (⌫)") { [weak self] in self?.deleteCurrent() },
        ])

        let detail = NSView()
        detail.wantsLayer = true
        detail.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor

        for view in [scroll, detail, toolbar, canvas, emptyLabel] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }
        content.addSubview(scroll)
        content.addSubview(detail)
        detail.addSubview(toolbar)
        detail.addSubview(canvas)
        detail.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalToConstant: 220),

            detail.leadingAnchor.constraint(equalTo: scroll.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detail.topAnchor.constraint(equalTo: content.topAnchor),
            detail.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            toolbar.topAnchor.constraint(equalTo: detail.topAnchor, constant: 12),
            toolbar.centerXAnchor.constraint(equalTo: detail.centerXAnchor),

            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 16),
            canvas.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -16),
            canvas.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -16),

            emptyLabel.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
        ])
    }

    // MARK: 목록

    private func reload(select item: CaptureItem?) {
        table.reloadData()
        if let item, let row = store.items.firstIndex(where: { $0.id == item.id }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
        showSelected()
    }

    @objc private func storeChanged() {
        guard !isPersisting else { return }
        // 새 캡처가 들어오면 그것을 보여 준다. 그 밖의 변경은 보던 것을 유지한다.
        let newest = store.items.first
        if let newest, newest.id != knownNewest {
            knownNewest = newest.id
            saveEdits()
            reload(select: newest)
        } else {
            let keep = shown.flatMap { current in store.items.first { $0.id == current.id } }
            reload(select: keep ?? newest)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("CaptureCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? CaptureCell ?? CaptureCell()
        cell.identifier = id
        let item = store.items[row]
        cell.thumbnail.image = store.thumbnail(for: item)
        cell.caption.stringValue = "\(Self.dateFormatter.string(from: item.date))  ·  \(item.width)×\(item.height)"
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        saveEdits()
        showSelected()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        store.url(for: store.items[row]) as NSURL
    }

    private var selectedItem: CaptureItem? {
        let row = table.selectedRow
        return row >= 0 && row < store.items.count ? store.items[row] : nil
    }

    private func showSelected() {
        guard let item = selectedItem, let image = store.image(for: item) else {
            shown = nil
            canvas.setImage(Self.blank, pixelScale: 1)
            canvas.isHidden = true
            emptyLabel.isHidden = !store.items.isEmpty
            return
        }
        guard item.id != shown?.id else { return }
        shown = item
        canvas.isHidden = false
        emptyLabel.isHidden = true
        canvas.setImage(image, pixelScale: item.scale)
    }

    /// 보던 캡처에 그린 표시를 이미지에 합쳐 저장한다.
    private func saveEdits() {
        guard let item = shown, canvas.hasEdits else { return }
        persist(item, canvas.render())
    }

    /// 목록 순서는 그대로 두고 이미지만 바꾼다. 저장 알림으로 선택이 바뀌지 않게 막는다.
    private func persist(_ item: CaptureItem, _ image: CGImage) {
        isPersisting = true
        store.replace(item, with: image)
        isPersisting = false
        if let row = store.items.firstIndex(where: { $0.id == item.id }) {
            table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        }
    }

    // MARK: 동작

    @objc func copyCurrent() {
        guard let item = selectedItem else { return }
        if canvas.hasEdits, item.id == shown?.id {
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

    @objc func deleteCurrent() {
        guard let item = selectedItem else { return }
        let row = table.selectedRow
        shown = nil
        canvas.setImage(Self.blank, pixelScale: 1)
        store.remove(item)
        let next = store.items.isEmpty ? nil : store.items[min(row, store.items.count - 1)]
        reload(select: next)
    }

    func undoAnnotation() { canvas.undo() }

    var isEditingText: Bool { canvas.isEditingText }

    func selectTool(_ tool: Tool) { canvas.tool = tool; window?.invalidateCursorRects(for: canvas) }

    func windowWillClose(_ notification: Notification) { saveEdits() }
}

/// 보관함 창의 단축키(⌘C, ⌘Z, ⌫, 도구 글자)를 받는다.
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
        if event.keyCode == 51 || event.keyCode == 117 { // ⌫, ⌦
            library.deleteCurrent()
        } else if let tool = Tool.forKeyCode(event.keyCode) {
            library.selectTool(tool)
        } else {
            super.keyDown(with: event)
        }
    }
}

final class CaptureCell: NSTableCellView {
    let thumbnail = NSImageView()
    let caption = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        thumbnail.imageScaling = .scaleProportionallyDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 4
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail
        for view in [thumbnail, caption] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            thumbnail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            thumbnail.bottomAnchor.constraint(equalTo: caption.topAnchor, constant: -4),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
