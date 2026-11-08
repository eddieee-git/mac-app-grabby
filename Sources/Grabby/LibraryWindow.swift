import AppKit
import Carbon

/// 캡처 탭 창. 캡처할 때마다 오른쪽 끝에 탭이 하나씩 늘어나고, 고른 탭을 보고, 이어서 편집하고, 다시 복사한다.
/// 표시가 있는 캡처는 원본과 표시를 따로 저장해 두어, 나중에 열어도 표시를 다시 고르고 고칠 수 있다.
final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    private let store = CaptureStore.shared
    private let canvas = AnnotationCanvas(image: LibraryWindowController.blank, pixelScale: 1)
    private let canvasScroll = ZoomScrollView()
    private let emptyLabel = NSTextField(labelWithString: L("아직 캡처가 없어요.\n메뉴바의 영역 캡처나 단축키로 화면을 캡처해 보세요."))
    private let tabStrip = NSStackView()
    private let tabScroll = NSScrollView()
    private let pinButton = NSButton()
    private let listButton = NSButton()
    private let scrollLeftButton = NSButton()
    private let scrollRightButton = NSButton()
    private let keepButton = NSButton()
    private let zoomLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private var query = ""
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
    private func focusCanvas() {
        window?.makeFirstResponder(canvas)
    }

    /// 다른 앱의 포커스는 그대로 두고 창만 앞에 띄운다(캡처 직후).
    func showWithoutFocus() {
        window?.orderFrontRegardless()
    }

    // MARK: 화면 구성

    private func build() {
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

    private func configure(_ b: NSButton, symbol: String, tip: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.bezelStyle = .texturedRounded
        b.toolTip = tip
        b.target = self
        b.action = action
    }

    private func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton()
        configure(b, symbol: symbol, tip: tip, action: action)
        return b
    }

    /// 창에 맞출 때는 보이는 영역 크기 그대로, 확대했을 때는 이미지 크기만큼 캔버스를 키워 스크롤한다.
    private func layoutCanvas() {
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
    private func reloadTabs() {
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

    @objc private func storeChanged() {
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

    private var selectedItem: CaptureItem? { store.items.first { $0.id == selectedID } }

    private func showSelected() {
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
    private func saveEdits() {
        guard let id = shownID, let item = store.items.first(where: { $0.id == id }), canvas.isDirty || canvas.isEditingText else { return }
        persist(item)
    }

    /// 탭 순서는 그대로 두고 이미지만 바꾼다. 저장 알림으로 탭을 다시 만들지 않게 막는다.
    private func persist(_ item: CaptureItem) {
        let flattened = canvas.render()
        isPersisting = true
        store.replace(item, with: flattened, original: canvas.image, annotations: canvas.annotations)
        isPersisting = false
        canvas.markSaved()
        tabs.first { $0.item.id == item.id }?.thumbnail = store.thumbnail(for: item)
    }

    // MARK: 동작

    /// 지금 보는 이미지(표시를 합친 것). 고른 부분이 있으면 그 부분만.
    private func currentImage() -> CGImage? {
        guard let item = selectedItem else { return nil }
        if let part = canvas.selectedImage() { return part }
        if item.id == shownID, canvas.isDirty || canvas.isEditingText { persist(item) }
        return store.image(for: item)
    }

    func copyCurrent() {
        guard let item = selectedItem else { return }
        let isPart = canvas.selectionRect != nil
        guard let image = currentImage() else { return }
        Clipboard.copy(image, scale: item.scale)
        Toast.show(isPart ? L("선택한 부분을 복사했어요") : L("복사했어요"), image: NSImage(cgImage: image, size: .zero))
    }

    /// 지금 탭을 파일로 저장한다. 그린 표시는 합치고, 고른 부분이 있으면 그 부분만 저장한다.
    func saveCurrent() {
        guard let item = selectedItem, let image = currentImage() else { return }
        ImageSaver.save(image, scale: item.scale, date: item.date) { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// 화면 가운데쯤에 실제 크기로 띄운다.
    func pinCurrent() {
        guard let item = selectedItem, let image = currentImage(), let screen = window?.screen ?? NSScreen.main else { return }
        let size = CGSize(width: CGFloat(image.width) / item.scale, height: CGFloat(image.height) / item.scale)
        let visible = screen.visibleFrame
        let frame = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        PinWindow.show(image, scale: item.scale, at: frame)
    }

    func recognizeCurrent() {
        guard let image = currentImage() else { return }
        Task { @MainActor in
            let text = await TextRecognizer.recognize(image)
            if text.isEmpty {
                Toast.show(L("글자를 찾지 못했어요"))
            } else {
                Clipboard.copy(text: text)
                let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
                Toast.show(L("글자를 복사했어요 · %@", String(firstLine.prefix(40))))
            }
        }
    }

    @objc private func searchChanged() {
        query = searchField.stringValue
        // 검색을 지우면 다시 캔버스로 돌아가 도구 단축키를 쓸 수 있게 한다.
        if query.isEmpty { DispatchQueue.main.async { [weak self] in self?.focusCanvas() } }
        reloadTabs()
        // 찾은 탭이 있는데 보던 탭이 빠졌으면 가장 최근 것을 보여 준다.
        if !tabs.contains(where: { $0.item.id == selectedID }), let last = tabs.last { select(last.item.id) }
        if let tab = tabs.first(where: { $0.item.id == selectedID }) {
            tabStrip.layoutSubtreeIfNeeded()
            tab.scrollToVisible(tab.bounds)
        }
    }

    @objc private func cropAction() {
        guard canvas.selectionRect != nil else {
            Toast.show(L("부분 선택(V)으로 남길 영역을 먼저 고르세요"))
            return
        }
        guard canvas.cropToSelection(), let item = selectedItem else { return }
        persist(item)
        // 저장한 결과를 다시 불러와 보여 준다.
        shownID = nil
        showSelected()
    }

    @objc private func noteAction() {
        guard let item = selectedItem, let window else { return }
        let alert = NSAlert()
        alert.messageText = L("메모")
        alert.informativeText = L("탭 이름 대신 보이고, 검색할 때 찾을 수 있어요.")
        let field = NSTextField(string: item.note ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.placeholderString = L("예: 회의 자료, 버그 화면")
        alert.accessoryView = field
        alert.addButton(withTitle: L("저장"))
        alert.addButton(withTitle: L("취소"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.store.setNote(item, field.stringValue)
        }
    }

    /// ⌘V: 클립보드의 이미지를 새 탭으로 넣는다.
    func pasteImage() {
        guard let (image, scale) = Clipboard.image() else {
            Toast.show(L("클립보드에 이미지가 없어요"))
            return
        }
        CaptureStore.shared.add(image, scale: scale)
        Toast.show(L("붙여 넣어 새 탭을 만들었어요"))
        store.indexText()
    }

    func beautifyCurrent() {
        guard let item = selectedItem, let image = currentImage() else { return }
        let pretty = Beautifier.apply(image, scale: item.scale)
        Clipboard.copy(pretty, scale: item.scale)
        Toast.show(L("꾸며서 복사했어요"), image: NSImage(cgImage: pretty, size: .zero))
    }

    @objc private func beautifyAction() { beautifyCurrent() }
    @objc private func copyAction() { copyCurrent() }
    @objc private func saveAction() { saveCurrent() }
    @objc private func pinAction() { pinCurrent() }
    @objc private func ocrAction() { recognizeCurrent() }
    @objc private func deleteAction() { deleteCurrent() }
    @objc private func zoomInAction() { canvas.zoomIn() }
    @objc private func zoomOutAction() { canvas.zoomOut() }
    @objc private func zoomFitAction() { canvas.zoomToFit() }
    @objc private func zoomActualAction() { canvas.zoomToActualSize() }

    @objc private func revealAction() {
        guard let item = selectedItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.url(for: item)])
    }

    @objc private func toggleKeep() {
        guard let item = selectedItem else { return }
        isPersisting = true
        store.setKept(item, !item.isKept)
        isPersisting = false
        reloadTabs()
        updateSelection()
    }

    /// 모든 캡처를 날짜별로 보여 주는 메뉴. 고르면 그 탭으로 간다.
    @objc private func showList() {
        let menu = NSMenu()
        if !store.items.isEmpty {
            let saveAll = NSMenuItem(title: L("모두 저장…"), action: #selector(saveAllAction), keyEquivalent: "")
            saveAll.target = self
            saveAll.image = NSImage(systemSymbolName: "square.and.arrow.down.on.square", accessibilityDescription: nil)
            menu.addItem(saveAll)
            let closeAll = NSMenuItem(title: L("모두 닫기…"), action: #selector(closeAllAction), keyEquivalent: "")
            closeAll.target = self
            closeAll.image = NSImage(systemSymbolName: "xmark.square", accessibilityDescription: nil)
            menu.addItem(closeAll)
            menu.addItem(.separator())
        }
        let locale = Locale(identifier: Localization.language == .korean ? "ko_KR" : "en_US")
        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.setLocalizedDateFormatFromTemplate("MMMMdEEE")
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeStyle = .short
        var lastDay: String?
        for item in store.items {
            let day = dayFormatter.string(from: item.date)
            if day != lastDay {
                if lastDay != nil { menu.addItem(.separator()) }
                let header = NSMenuItem(title: day, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
                lastDay = day
            }
            let title = "\(item.isKept ? "★ " : "")\(timeFormatter.string(from: item.date))  ·  \(item.width)×\(item.height)"
            let entry = NSMenuItem(title: title, action: #selector(listPicked(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.id
            entry.state = item.id == selectedID ? .on : .off
            if let thumb = store.thumbnail(for: item) {
                let size = thumb.size, h: CGFloat = 32
                entry.image = NSImage(size: NSSize(width: min(64, size.width * h / max(size.height, 1)), height: h), flipped: false) { rect in
                    thumb.draw(in: rect)
                    return true
                }
            }
            menu.addItem(entry)
        }
        if store.items.isEmpty {
            let empty = NSMenuItem(title: L("아직 캡처가 없어요."), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: listButton.bounds.height + 4), in: listButton)
    }

    /// 모든 캡처를 그린 표시까지 합친 이미지로 한 폴더에 저장한다.
    @objc private func saveAllAction() {
        saveEdits()
        let entries = store.items.compactMap { item in store.image(for: item).map { ($0, item.scale, item.date) } }
        ImageSaver.saveAll(entries) { [weak self] in self?.window?.makeKeyAndOrderFront(nil) }
    }

    /// 모든 탭을 지운다. 지우기 전에 항상 묻고, ★ 고정한 캡처가 있으면 남길지 고르게 한다.
    @objc private func closeAllAction() {
        guard let window else { return }
        let keptCount = store.items.filter(\.isKept).count
        let alert = NSAlert()
        alert.messageText = L("모든 캡처를 닫을까요?")
        alert.informativeText = L("탭 %ld개를 삭제해요. 삭제한 캡처는 되돌릴 수 없어요.", store.items.count)
        if keptCount > 0 {
            alert.addButton(withTitle: L("★ 고정한 것은 남기기"))
            alert.addButton(withTitle: L("모두 삭제"))
        } else {
            alert.addButton(withTitle: L("모두 삭제"))
        }
        alert.addButton(withTitle: L("취소"))
        alert.buttons.first?.keyEquivalent = ""
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            let keepKept: Bool
            switch response {
            case .alertFirstButtonReturn: keepKept = keptCount > 0
            case .alertSecondButtonReturn where keptCount > 0: keepKept = false
            default: return
            }
            self.shownID = nil
            self.selectedID = nil
            self.canvas.load(Self.blank, pixelScale: 1)
            self.isPersisting = true
            let removed = self.store.removeAll(keepKept: keepKept)
            self.isPersisting = false
            self.knownNewest = self.store.items.first?.id
            self.reloadTabs()
            self.select(self.store.items.first?.id)
            Toast.show(L("탭 %ld개를 닫았어요", removed))
        }
    }

    @objc private func listPicked(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { select(id) }
    }

    /// ⌫: 고른 표시가 있으면 그것만, 없으면 탭을 지운다.
    func deleteKey() {
        if !canvas.deleteSelected() { deleteCurrent() }
    }

    func deleteCurrent() {
        if let selectedID { delete(selectedID) }
    }

    /// 설정에 따라 한 번 묻는다. '다시 묻지 않기'를 고르면 설정을 끈다.
    private func confirmDelete() -> Bool {
        let settings = AppSettings.shared
        guard settings.confirmDelete else { return true }
        let alert = NSAlert()
        alert.messageText = L("이 캡처를 삭제할까요?")
        alert.informativeText = L("삭제한 캡처는 되돌릴 수 없어요.")
        alert.addButton(withTitle: L("삭제"))
        alert.addButton(withTitle: L("취소"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L("다시 묻지 않기")
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on { settings.confirmDelete = false }
        return confirmed
    }

    /// 탭을 지우고 오른쪽 탭(없으면 왼쪽 탭)을 고른다.
    private func delete(_ id: UUID) {
        guard let item = store.items.first(where: { $0.id == id }), confirmDelete() else { return }
        let index = tabs.firstIndex { $0.item.id == id } ?? 0
        let wasSelected = id == selectedID
        if wasSelected {
            shownID = nil
            canvas.load(Self.blank, pixelScale: 1)
        }
        isPersisting = true
        store.remove(item)
        isPersisting = false
        knownNewest = store.items.first?.id
        reloadTabs()
        if wasSelected {
            let next = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].item.id
            selectedID = nil
            select(next)
        } else {
            select(selectedID, reveal: false)
        }
    }

    /// 탭 줄을 보이는 너비의 80%만큼 옮긴다.
    private func scrollTabs(by direction: CGFloat) {
        let clip = tabScroll.contentView
        let maxX = max(0, tabStrip.frame.width - clip.bounds.width)
        let x = min(max(clip.bounds.origin.x + direction * clip.bounds.width * 0.8, 0), maxX)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            clip.animator().setBoundsOrigin(NSPoint(x: x, y: 0))
        }
        tabScroll.reflectScrolledClipView(clip)
    }

    @objc private func scrollTabsLeft() { scrollTabs(by: -1) }
    @objc private func scrollTabsRight() { scrollTabs(by: 1) }

    /// 더 볼 탭이 있는 쪽 화살표만 켠다. 탭이 모두 보이면 화살표를 숨긴다.
    @objc private func updateTabArrows() {
        let clip = tabScroll.contentView
        let overflow = tabStrip.frame.width > clip.bounds.width + 1
        scrollLeftButton.isHidden = !overflow
        scrollRightButton.isHidden = !overflow
        scrollLeftButton.isEnabled = clip.bounds.origin.x > 1
        scrollRightButton.isEnabled = clip.bounds.maxX < tabStrip.frame.width - 1
    }

    @objc private func pinToggled() { setPinned(pinButton.state == .on) }

    private func setPinned(_ pinned: Bool) {
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

/// 캔버스를 담는 스크롤 영역. 크기가 바뀔 때마다 캔버스 크기를 다시 맞춘다.
final class ZoomScrollView: NSScrollView {
    var onTile: (() -> Void)?

    override func tile() {
        super.tile()
        onTile?()
    }
}

/// 탭 창의 단축키를 받는다.
final class LibraryWindow: NSWindow {
    weak var library: LibraryWindowController?

    @objc func copy(_ sender: Any?) { library?.copyCurrent() }
    @objc func paste(_ sender: Any?) { library?.pasteImage() }
    @objc func saveDocument(_ sender: Any?) { library?.saveCurrent() }
    @objc func undo(_ sender: Any?) { library?.undoAnnotation() }
    @objc func redo(_ sender: Any?) { library?.redoAnnotation() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let library, mods.contains(.command), !library.isEditingText else { return super.performKeyEquivalent(with: event) }
        switch KeyLetter.of(event) {
        case "p" where mods == .command: library.pinCurrent()
        case "t" where mods == .command: library.recognizeCurrent()
        case "b" where mods == .command: library.beautifyCurrent()
        case "=": library.zoom { $0.zoomIn() }
        case "-": library.zoom { $0.zoomOut() }
        case "0" where mods == .command: library.zoom { $0.zoomToActualSize() }
        case "9" where mods == .command: library.zoom { $0.zoomToFit() }
        case "z" where mods == [.command, .shift]: library.redoAnnotation()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let library, !library.isEditingText,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete: library.deleteKey()
        case kVK_Escape: library.clearSelections()
        case kVK_LeftArrow: library.moveSelection(by: -1)
        case kVK_RightArrow: library.moveSelection(by: 1)
        default:
            if let tool = Tool.forLetter(KeyLetter.of(event)) { library.selectTool(tool) } else { super.keyDown(with: event) }
        }
    }
}

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
