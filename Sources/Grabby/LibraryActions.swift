import AppKit

/// 탭 창의 동작: 복사·저장·핀·글자 복사·꾸미기·자르기·메모·붙여넣기·모두 저장·모두 닫기·삭제.
extension LibraryWindowController {
    // MARK: 동작

    /// 지금 보는 이미지(표시를 합친 것). 고른 부분이 있으면 그 부분만.
    func currentImage() -> CGImage? {
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

    @objc func searchChanged() {
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

    @objc func cropAction() {
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

    @objc func noteAction() {
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

    @objc func beautifyAction() { beautifyCurrent() }
    @objc func copyAction() { copyCurrent() }
    @objc func saveAction() { saveCurrent() }
    @objc func pinAction() { pinCurrent() }
    @objc func ocrAction() { recognizeCurrent() }
    @objc func deleteAction() { deleteCurrent() }
    @objc func zoomInAction() { canvas.zoomIn() }
    @objc func zoomOutAction() { canvas.zoomOut() }
    @objc func zoomFitAction() { canvas.zoomToFit() }
    @objc func zoomActualAction() { canvas.zoomToActualSize() }

    @objc func revealAction() {
        guard let item = selectedItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.url(for: item)])
    }

    @objc func toggleKeep() {
        guard let item = selectedItem else { return }
        isPersisting = true
        store.setKept(item, !item.isKept)
        isPersisting = false
        reloadTabs()
        updateSelection()
    }

    /// 모든 캡처를 날짜별로 보여 주는 메뉴. 고르면 그 탭으로 간다.
    @objc func showList() {
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
    @objc func saveAllAction() {
        saveEdits()
        let entries = store.items.compactMap { item in store.image(for: item).map { ($0, item.scale, item.date) } }
        ImageSaver.saveAll(entries) { [weak self] in self?.window?.makeKeyAndOrderFront(nil) }
    }

    /// 모든 탭을 지운다. 지우기 전에 항상 묻고, ★ 고정한 캡처가 있으면 남길지 고르게 한다.
    @objc func closeAllAction() {
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

    @objc func listPicked(_ sender: NSMenuItem) {
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
    func confirmDelete() -> Bool {
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
    func delete(_ id: UUID) {
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
    func scrollTabs(by direction: CGFloat) {
        let clip = tabScroll.contentView
        let maxX = max(0, tabStrip.frame.width - clip.bounds.width)
        let x = min(max(clip.bounds.origin.x + direction * clip.bounds.width * 0.8, 0), maxX)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            clip.animator().setBoundsOrigin(NSPoint(x: x, y: 0))
        }
        tabScroll.reflectScrolledClipView(clip)
    }

    @objc func scrollTabsLeft() { scrollTabs(by: -1) }
    @objc func scrollTabsRight() { scrollTabs(by: 1) }

    /// 더 볼 탭이 있는 쪽 화살표만 켠다. 탭이 모두 보이면 화살표를 숨긴다.
    @objc func updateTabArrows() {
        let clip = tabScroll.contentView
        let overflow = tabStrip.frame.width > clip.bounds.width + 1
        scrollLeftButton.isHidden = !overflow
        scrollRightButton.isHidden = !overflow
        scrollLeftButton.isEnabled = clip.bounds.origin.x > 1
        scrollRightButton.isEnabled = clip.bounds.maxX < tabStrip.frame.width - 1
    }
}
