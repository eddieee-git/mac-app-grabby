import AppKit
import Carbon

/// 캡처 탭 창. 캡처할 때마다 오른쪽 끝에 탭이 하나씩 늘어나고, 고른 탭을 보고, 이어서 편집하고, 다시 복사한다.
/// 표시가 있는 캡처는 원본과 표시를 따로 저장해 두어, 나중에 열어도 표시를 다시 고르고 고칠 수 있다.
final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    let store = CaptureStore.shared
    let canvas = AnnotationCanvas(image: LibraryWindowController.blank, pixelScale: 1)
    let canvasScroll = ZoomScrollView()
    let emptyLabel = NSTextField(labelWithString: L("아직 캡처가 없어요.\n메뉴바의 영역 캡처나 단축키로 화면을 캡처해 보세요."))
    let tabStrip = NSStackView()
    let tabScroll = NSScrollView()
    let pinButton = NSButton()
    let listButton = NSButton()
    let scrollLeftButton = NSButton()
    let scrollRightButton = NSButton()
    let keepButton = NSButton()
    let zoomLabel = NSTextField(labelWithString: "")
    let searchField = NSSearchField()
    var query = ""
    var tabs: [CaptureTab] = []
    var selectedID: UUID?
    var shownID: UUID?
    var knownNewest: UUID?
    var isPersisting = false

    let pinKey = "libraryPinned"

    static let blank: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    init() {
        let window = LibraryWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Grabby"
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        if !window.setFrameUsingName("CaptureTabs") { window.center() }
        window.setFrameAutosaveName("CaptureTabs")
        window.delegate = self
        window.library = self
        build()
        window.initialFirstResponder = canvas
        setPinned(UserDefaults.standard.bool(forKey: pinKey))
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: CaptureStore.didChange, object: nil)
        knownNewest = store.items.first?.id
        reloadTabs()
        select(store.items.first?.id)
        store.indexText()
    }

    required init?(coder: NSCoder) { fatalError() }

    var isVisible: Bool { window?.isVisible == true }

    /// 앱을 앞으로 가져와 창을 연다(메뉴에서 열 때).
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        focusCanvas()
    }

    /// 도구 단축키(V, A, R…)가 검색 칸이 아니라 캔버스로 가게 한다.
    func focusCanvas() {
        window?.makeFirstResponder(canvas)
    }

    /// 다른 앱의 포커스는 그대로 두고 창만 앞에 띄운다(캡처 직후).
    func showWithoutFocus() {
        window?.orderFrontRegardless()
    }

    // MARK: 화면 구성

    func build() {
        guard let content = window?.contentView else { return }

        // 위: 모든 캡처 목록 · 탭 · 항상 위에
        tabStrip.orientation = .horizontal
        tabStrip.spacing = 4
        tabStrip.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 8)
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

        configure(listButton, symbol: "square.grid.2x2", tip: L("모든 캡처 보기"), action: #selector(showList))
        configure(scrollLeftButton, symbol: "chevron.left", tip: L("앞 탭 보기"), action: #selector(scrollTabsLeft))
        configure(scrollRightButton, symbol: "chevron.right", tip: L("뒤 탭 보기"), action: #selector(scrollTabsRight))
        for b in [scrollLeftButton, scrollRightButton] { b.isBordered = false }
        // 탭 줄을 스크롤할 때마다 화살표를 쓸 수 있는지 다시 확인한다.
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(updateTabArrows), name: NSView.boundsDidChangeNotification, object: clip)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTabArrows), name: NSView.frameDidChangeNotification, object: tabStrip)
        tabStrip.postsFrameChangedNotifications = true
        tabScroll.hasHorizontalScroller = false
        configure(pinButton, symbol: "pin", tip: L("창을 항상 위에 두기"), action: #selector(pinToggled))
        pinButton.setButtonType(.toggle)
        pinButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: L("항상 위에"))
        pinButton.isBordered = false
        // 항상 위에 핀은 창 제목 줄 오른쪽에 둔다.
        let accessory = NSTitlebarAccessoryViewController()
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        pinButton.frame = NSRect(x: 4, y: 2, width: 26, height: 24)
        holder.addSubview(pinButton)
        accessory.view = holder
        accessory.layoutAttribute = .trailing
        window?.addTitlebarAccessoryViewController(accessory)

        searchField.placeholderString = L("글자·메모 검색")
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.toolTip = L("캡처 속 글자나 메모로 찾아요")

        let header = NSView()
        let topDivider = NSBox()
        topDivider.boxType = .separator

        // 가운데: 편집 도구와 이미지
        canvas.tool = .select
        canvas.allowsZoom = true
        canvas.onZoomChange = { [weak self] in self?.layoutCanvas() }
        let toolbar = EditToolbar(canvas: canvas, tools: Tool.allCases, actions: [])
        canvasScroll.documentView = canvas
        canvasScroll.hasVerticalScroller = true
        canvasScroll.hasHorizontalScroller = true
        canvasScroll.autohidesScrollers = true
        canvasScroll.drawsBackground = false
        canvasScroll.onTile = { [weak self] in self?.layoutCanvas() }
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor

        // 아래: 동작 버튼과 확대·축소
        configure(keepButton, symbol: "star", tip: L("고정 (★) · 보관 개수를 넘어도 지우지 않아요"), action: #selector(toggleKeep))
        keepButton.setButtonType(.toggle)
        keepButton.alternateImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
        let actions = NSStackView(views: [
            button("doc.on.doc", L("복사 (⌘C) · 고른 부분이 있으면 그 부분만"), #selector(copyAction)),
            button("square.and.arrow.down", L("파일로 저장 (⌘S) · 고른 부분이 있으면 그 부분만"), #selector(saveAction)),
            button("pin", L("화면에 띄우기 (⌘P)"), #selector(pinAction)),
            button("text.viewfinder", L("글자 복사 (⌘T) · 이미지 속 글자를 인식해 복사"), #selector(ocrAction)),
            button("wand.and.stars", L("꾸며서 복사 (⌘B) · 여백·배경·그림자를 넣어 복사"), #selector(beautifyAction)),
            button("crop", L("자르기 · 부분 선택한 영역만 남겨요"), #selector(cropAction)),
            button("note.text", L("메모 달기 · 탭 이름으로 보이고 검색돼요"), #selector(noteAction)),
            keepButton,
            button("folder", L("Finder에서 보기"), #selector(revealAction)),
            button("trash", L("삭제 (⌫)"), #selector(deleteAction)),
        ])
        actions.spacing = 6
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.alignment = .center
        let zoom = NSStackView(views: [
            button("minus.magnifyingglass", L("축소 (⌘-)"), #selector(zoomOutAction)),
            zoomLabel,
            button("plus.magnifyingglass", L("확대 (⌘+)"), #selector(zoomInAction)),
            button("arrow.up.left.and.down.right.magnifyingglass", L("창에 맞추기 (⌘9)"), #selector(zoomFitAction)),
            button("1.magnifyingglass", L("실제 크기 (⌘0)"), #selector(zoomActualAction)),
        ])
        zoom.spacing = 4
        let footer = NSView()
        let bottomDivider = NSBox()
        bottomDivider.boxType = .separator

        for view in [header, listButton, searchField, scrollLeftButton, tabScroll, scrollRightButton, topDivider, toolbar, canvasScroll, emptyLabel,
                     bottomDivider, footer, actions, zoom, zoomLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        content.addSubview(header)
        header.addSubview(listButton)
        header.addSubview(searchField)
        header.addSubview(scrollLeftButton)
        header.addSubview(tabScroll)
        header.addSubview(scrollRightButton)
        content.addSubview(topDivider)
        content.addSubview(toolbar)
        content.addSubview(canvasScroll)
        content.addSubview(emptyLabel)
        content.addSubview(bottomDivider)
        content.addSubview(footer)
        footer.addSubview(actions)
        footer.addSubview(zoom)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 56),

            listButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            listButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: listButton.trailingAnchor, constant: 6),
            searchField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 150),
            scrollLeftButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 6),
            scrollLeftButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            scrollLeftButton.widthAnchor.constraint(equalToConstant: 20),
            tabScroll.leadingAnchor.constraint(equalTo: scrollLeftButton.trailingAnchor, constant: 2),
            tabScroll.trailingAnchor.constraint(equalTo: scrollRightButton.leadingAnchor, constant: -2),
            tabScroll.topAnchor.constraint(equalTo: header.topAnchor, constant: 6),
            tabScroll.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -6),
            scrollRightButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            scrollRightButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            scrollRightButton.widthAnchor.constraint(equalToConstant: 20),

            topDivider.topAnchor.constraint(equalTo: header.bottomAnchor),
            topDivider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            toolbar.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 10),
            toolbar.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            canvasScroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            canvasScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            canvasScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            canvasScroll.bottomAnchor.constraint(equalTo: bottomDivider.topAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: canvasScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: canvasScroll.centerYAnchor),

            bottomDivider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottomDivider.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 40),
            actions.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            actions.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            zoom.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            zoom.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            zoomLabel.widthAnchor.constraint(equalToConstant: 44),
        ])
    }

    func configure(_ b: NSButton, symbol: String, tip: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.bezelStyle = .texturedRounded
        b.toolTip = tip
        b.target = self
        b.action = action
    }

    func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton()
        configure(b, symbol: symbol, tip: tip, action: action)
        return b
    }

    /// 창에 맞출 때는 보이는 영역 크기 그대로, 확대했을 때는 이미지 크기만큼 캔버스를 키워 스크롤한다.
    func layoutCanvas() {
        let visible = canvasScroll.contentSize
        var size = visible
        if let zoom = canvas.zoom {
            let image = canvas.imageSize
            size = CGSize(width: max(visible.width, (image.width * zoom).rounded()), height: max(visible.height, (image.height * zoom).rounded()))
        }
        if canvas.frame.size != size { canvas.frame = CGRect(origin: .zero, size: size) }
        canvas.needsDisplay = true
        zoomLabel.stringValue = canvas.zoom.map { "\(Int(($0 * 100).rounded()))%" } ?? L("맞춤")
    }

    // MARK: 탭

    /// 오래된 것이 왼쪽, 새 캡처가 오른쪽 끝에 오도록 탭을 다시 만든다.
    func reloadTabs() {
        for tab in tabs { tab.removeFromSuperview() }
        tabs = store.items.reversed().filter { $0.matches(query) }.map { item in
            let tab = CaptureTab(item: item, thumbnail: store.thumbnail(for: item), fileURL: store.url(for: item))
            tab.onSelect = { [weak self] in self?.select(item.id) }
            tab.onClose = { [weak self] in self?.delete(item.id) }
            tab.onDoubleClick = { [weak self] in self?.copyCurrent() }
            return tab
        }
        for tab in tabs { tabStrip.addArrangedSubview(tab) }
        updateSelection()
    }

    func select(_ id: UUID?, reveal: Bool = true) {
        if id != selectedID { saveEdits() }
        selectedID = id.flatMap { id in store.items.contains { $0.id == id } ? id : nil }
        updateSelection()
        showSelected()
        if reveal, let tab = tabs.first(where: { $0.item.id == selectedID }) {
            tabStrip.layoutSubtreeIfNeeded()
            tab.scrollToVisible(tab.bounds)
        }
    }

    func updateSelection() {
        for tab in tabs { tab.isSelected = tab.item.id == selectedID }
        let kept = selectedItem?.isKept == true
        keepButton.state = kept ? .on : .off
        keepButton.contentTintColor = kept ? .systemYellow : nil
    }

    /// 왼쪽(-1)이나 오른쪽(+1) 탭으로 옮긴다.
    func moveSelection(by offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.item.id == selectedID }) else { return }
        let next = min(max(index + offset, 0), tabs.count - 1)
        select(tabs[next].item.id)
    }

    @objc func storeChanged() {
        guard !isPersisting else { return }
        // 새 캡처가 들어오면 그 탭을 고른다. 그 밖의 변경은 보던 탭을 유지한다.
        let newest = store.items.first
        reloadTabs()
        if let newest, newest.id != knownNewest {
            knownNewest = newest.id
            // 검색 중이면 새 캡처가 보이도록 검색을 지운다.
            if !query.isEmpty, !newest.matches(query) {
                query = ""
                searchField.stringValue = ""
                reloadTabs()
            }
            select(newest.id)
        } else {
            select(selectedID ?? newest?.id, reveal: false)
        }
    }

    var selectedItem: CaptureItem? { store.items.first { $0.id == selectedID } }

    func showSelected() {
        guard let item = selectedItem, let editable = store.editable(for: item) else {
            shownID = nil
            canvas.load(Self.blank, pixelScale: 1)
            canvasScroll.isHidden = true
            emptyLabel.isHidden = !store.items.isEmpty
            return
        }
        guard item.id != shownID else { return }
        shownID = item.id
        canvasScroll.isHidden = false
        emptyLabel.isHidden = true
        canvas.load(editable.image, pixelScale: item.scale, annotations: editable.annotations)
        layoutCanvas()
    }

    /// 보던 캡처의 표시가 바뀌었으면 저장한다. 원본과 표시도 함께 두어 다시 고칠 수 있게 한다.
    func saveEdits() {
        guard let id = shownID, let item = store.items.first(where: { $0.id == id }), canvas.isDirty || canvas.isEditingText else { return }
        persist(item)
    }

    /// 탭 순서는 그대로 두고 이미지만 바꾼다. 저장 알림으로 탭을 다시 만들지 않게 막는다.
    func persist(_ item: CaptureItem) {
        let flattened = canvas.render()
        isPersisting = true
        store.replace(item, with: flattened, original: canvas.image, annotations: canvas.annotations)
        isPersisting = false
        canvas.markSaved()
        tabs.first { $0.item.id == item.id }?.thumbnail = store.thumbnail(for: item)
    }

    @objc func pinToggled() { setPinned(pinButton.state == .on) }

    func setPinned(_ pinned: Bool) {
        pinButton.state = pinned ? .on : .off
        pinButton.contentTintColor = pinned ? .controlAccentColor : nil
        window?.level = pinned ? .floating : .normal
        UserDefaults.standard.set(pinned, forKey: pinKey)
    }

    func undoAnnotation() { canvas.undo() }
    func redoAnnotation() { canvas.redo() }
    func zoom(_ action: (AnnotationCanvas) -> Void) { action(canvas) }

    /// Esc: 고른 표시나 부분 선택을 푼다.
    func clearSelections() { _ = canvas.clearSelections() }

    var isEditingText: Bool { canvas.isEditingText }

    func selectTool(_ tool: Tool) { canvas.tool = tool; window?.invalidateCursorRects(for: canvas) }

    func windowWillClose(_ notification: Notification) { saveEdits() }
}
