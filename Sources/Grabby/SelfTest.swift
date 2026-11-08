import AppKit
import Carbon

// 자동 점검. Xcode 없이(Command Line Tools만으로) 돌릴 수 있게 앱 안에 둔다.
// 실행: ./scripts/test.sh  (또는 swift run Grabby --self-test)
// 실제 보관함과 설정은 건드리지 않는다(보관함은 임시 폴더를 쓴다).

@MainActor
enum SelfTest {
    private static var failures: [String] = []
    private static var count = 0
    private static var current = ""

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "", line: Int = #line) {
        count += 1
        let ok = (try? condition()) ?? false
        if !ok { failures.append("\(current) (줄 \(line)) \(message)") }
    }

    static func run() -> Int32 {
        EventLog.isEnabled = false
        let suites: [(String, () throws -> Void)] = [
            ("AnnotationTests.codableRoundTrip", SelfTest_AnnotationTests.test_codableRoundTrip),
            ("AnnotationTests.paletteColorStaysSystemColor", SelfTest_AnnotationTests.test_paletteColorStaysSystemColor),
            ("AnnotationTests.unknownKindFailsInsteadOfCrashing", SelfTest_AnnotationTests.test_unknownKindFailsInsteadOfCrashing),
            ("AnnotationTests.offsetMovesEveryPoint", SelfTest_AnnotationTests.test_offsetMovesEveryPoint),
            ("AnnotationTests.colorAndWidthChanges", SelfTest_AnnotationTests.test_colorAndWidthChanges),
            ("AnnotationTests.paletteEntries", SelfTest_AnnotationTests.test_paletteEntries),
            ("CanvasTests.deleteUndoRedo", SelfTest_CanvasTests.test_deleteUndoRedo),
            ("CanvasTests.recolorSelectedIsUndoable", SelfTest_CanvasTests.test_recolorSelectedIsUndoable),
            ("CanvasTests.cropKeepsMarksInPlace", SelfTest_CanvasTests.test_cropKeepsMarksInPlace),
            ("CanvasTests.renderKeepsResolution", SelfTest_CanvasTests.test_renderKeepsResolution),
            ("CanvasTests.selectedImageUsesSelection", SelfTest_CanvasTests.test_selectedImageUsesSelection),
            ("CanvasTests.beautifyAddsPadding", SelfTest_CanvasTests.test_beautifyAddsPadding),
            ("KeyTests.latinLetters", SelfTest_KeyTests.test_latinLetters),
            ("KeyTests.koreanInputMapsToKeyLetter", SelfTest_KeyTests.test_koreanInputMapsToKeyLetter),
            ("KeyTests.questionMarkAndSlash", SelfTest_KeyTests.test_questionMarkAndSlash),
            ("KeyTests.fallsBackToKeyPosition", SelfTest_KeyTests.test_fallsBackToKeyPosition),
            ("KeyTests.everyToolHasAShortcut", SelfTest_KeyTests.test_everyToolHasAShortcut),
            ("KeyTests.systemScreenshotShortcutsAreRejected", SelfTest_KeyTests.test_systemScreenshotShortcutsAreRejected),
            ("KeyTests.defaultShortcutsDoNotCollide", SelfTest_KeyTests.test_defaultShortcutsDoNotCollide),
            ("KeyTests.displayText", SelfTest_KeyTests.test_displayText),
            ("KeyTests.versionComparison", SelfTest_KeyTests.test_versionComparison),
            ("StoreTests.pruneKeepsNewestAndKept", SelfTest_StoreTests.test_pruneKeepsNewestAndKept),
            ("StoreTests.removeAllKeepsKeptWhenAsked", SelfTest_StoreTests.test_removeAllKeepsKeptWhenAsked),
            ("StoreTests.editableKeepsOriginalAndMarks", SelfTest_StoreTests.test_editableKeepsOriginalAndMarks),
            ("StoreTests.reloadsFromDisk", SelfTest_StoreTests.test_reloadsFromDisk),
            ("StoreTests.oldIndexWithoutNewFieldsStillLoads", SelfTest_StoreTests.test_oldIndexWithoutNewFieldsStillLoads),
            ("StoreTests.searchMatchesNoteAndText", SelfTest_StoreTests.test_searchMatchesNoteAndText),
        ]
        for (name, test) in suites {
            current = name
            do { try test() } catch { failures.append("\(name): \(error)") }
        }
        print("점검 \(suites.count)개 묶음, 확인 \(count)개")
        if failures.isEmpty {
            print("✓ 모두 통과")
            return 0
        }
        for failure in failures { print("✘ \(failure)") }
        return 1
    }

    struct Missing: Error {}
}

@MainActor
enum SelfTest_AnnotationTests {
    static func expect(_ c: @autoclosure () throws -> Bool, _ m: String = "", line: Int = #line) { SelfTest.expect(try c(), m, line: line) }
    static func require<T>(_ v: T?) throws -> T { guard let v else { throw SelfTest.Missing() }; return v }

    static let all: [Annotation] = [
        .arrow(from: CGPoint(x: 1, y: 2), to: CGPoint(x: 30, y: 40), color: .systemRed, width: 4),
        .line(from: .zero, to: CGPoint(x: 10, y: 0), color: .systemBlue, width: 2),
        .rect(CGRect(x: 5, y: 5, width: 20, height: 10), color: .systemGreen, width: 8),
        .ellipse(CGRect(x: 0, y: 0, width: 50, height: 30), color: .black, width: 4),
        .pen([CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4), CGPoint(x: 9, y: 1)], color: .white, width: 2),
        .text("안녕 Grabby", origin: CGPoint(x: 12, y: 8), color: .systemYellow, size: 32),
        .step(center: CGPoint(x: 20, y: 20), number: 3, color: .systemRed, level: 2),
        .highlight(CGRect(x: 1, y: 1, width: 5, height: 5), color: .systemYellow),
        .mosaic(CGRect(x: 2, y: 2, width: 8, height: 8)),
        .blur(CGRect(x: 3, y: 3, width: 9, height: 9)),
        .arrow(from: .zero, to: CGPoint(x: 5, y: 5), color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1), width: 4),
    ]

    private static func json(_ value: [Annotation]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    static func test_codableRoundTrip() throws {
        let data = try json(SelfTest_AnnotationTests.all)
        let decoded = try JSONDecoder().decode([Annotation].self, from: data)
        expect(decoded.count == SelfTest_AnnotationTests.all.count)
        expect(try json(decoded) == data)
    }

    static func test_paletteColorStaysSystemColor() throws {
        let data = try json([.rect(.zero, color: .systemRed, width: 4)])
        let decoded = try JSONDecoder().decode([Annotation].self, from: data)
        // 팔레트 색은 번호로 저장해서 다크 모드에 맞춰 바뀌는 시스템 색 그대로 돌아와야 한다.
        expect(decoded.first?.color == .systemRed)
    }

    static func test_unknownKindFailsInsteadOfCrashing() {
        let bad = Data(#"[{"kind":"triangle"}]"#.utf8)
        expect((try? JSONDecoder().decode([Annotation].self, from: bad)) == nil)
    }

    static func test_offsetMovesEveryPoint() throws {
        let moved = SelfTest_AnnotationTests.all.map { $0.offsetBy(dx: 10, dy: -5) }
        for (before, after) in zip(SelfTest_AnnotationTests.all, moved) {
            let a = AnnotationCanvas.bounds(of: before), b = AnnotationCanvas.bounds(of: after)
            expect(abs(b.minX - a.minX - 10) < 0.001)
            expect(abs(b.minY - a.minY + 5) < 0.001)
        }
    }

    static func test_paletteEntries() {
        // 사용자 팔레트 색은 "#RRGGBB"로 저장하고 그대로 돌아와야 한다(Cloudflare 주황 #F38020).
        let orange = AppSettings.color(from: "#F38020")
        expect(orange != nil)
        expect(AppSettings.hex(orange!) == "#F38020")
        expect(AppSettings.color(from: "system:0") == .systemRed)
        expect(AppSettings.color(from: "system:99") == nil)
        expect(AppSettings.color(from: "#ZZZZZZ") == nil)
        expect(AppSettings.defaultPalette.count == AnnotationCanvas.systemColors.count)
    }

    static func test_colorAndWidthChanges() {
        let arrow = Annotation.arrow(from: .zero, to: CGPoint(x: 5, y: 5), color: .systemRed, width: 4)
        expect(arrow.withColor(.systemBlue).color == .systemBlue)
        expect(arrow.withWidthLevel(2).widthLevel == 2)
        let text = Annotation.text("a", origin: .zero, color: .black, size: 20)
        expect(text.withWidthLevel(0).widthLevel == 0)
        // 모자이크는 색이 없고 바뀌지 않는다.
        expect(Annotation.mosaic(.zero).withColor(.systemRed).color == nil)
    }
}

@MainActor
enum SelfTest_CanvasTests {
    static func expect(_ c: @autoclosure () throws -> Bool, _ m: String = "", line: Int = #line) { SelfTest.expect(try c(), m, line: line) }
    static func require<T>(_ v: T?) throws -> T { guard let v else { throw SelfTest.Missing() }; return v }

    private static func image(width: Int, height: Int) -> CGImage {
        ScreenShot.white(width: width, height: height)!
    }

    private static func canvas(_ annotations: [Annotation] = []) -> AnnotationCanvas {
        let canvas = AnnotationCanvas(image: image(width: 200, height: 100), pixelScale: 2)
        canvas.load(image(width: 200, height: 100), pixelScale: 2, annotations: annotations)
        return canvas
    }

    static func test_deleteUndoRedo() {
        let c = canvas(Array(SelfTest_AnnotationTests.all.prefix(2)))
        c.selectedIndex = 0
        expect(c.deleteSelected())
        expect(c.annotations.count == 1)
        expect(c.isDirty)
        c.undo()
        expect(c.annotations.count == 2)
        c.redo()
        expect(c.annotations.count == 1)
        // 고른 게 없으면 지우지 않는다.
        expect(!c.deleteSelected())
    }

    static func test_recolorSelectedIsUndoable() {
        let c = canvas([.rect(CGRect(x: 0, y: 0, width: 10, height: 10), color: .systemRed, width: 4)])
        c.selectedIndex = 0
        c.applyColor(3)
        expect(c.annotations.first?.color == AnnotationCanvas.palette[3])
        c.undo()
        expect(c.annotations.first?.color == .systemRed)
    }

    static func test_cropKeepsMarksInPlace() {
        let c = canvas([.rect(CGRect(x: 30, y: 20, width: 10, height: 10), color: .systemRed, width: 4)])
        c.selectionRect = CGRect(x: 20, y: 10, width: 40, height: 30)
        expect(c.cropToSelection())
        // 포인트 40×30, 배율 2 → 픽셀 80×60
        expect(c.image.width == 80 && c.image.height == 60)
        expect(AnnotationCanvas.bounds(of: c.annotations[0]).minX == 10 - 2)
        expect(c.selectionRect == nil)
    }

    static func test_renderKeepsResolution() {
        let c = canvas([.arrow(from: .zero, to: CGPoint(x: 50, y: 30), color: .systemRed, width: 4)])
        let out = c.render()
        expect(out.width == 200 && out.height == 100)
    }

    static func test_selectedImageUsesSelection() {
        let c = canvas()
        c.selectionRect = CGRect(x: 10, y: 10, width: 25, height: 15)
        expect(c.selectedImage()?.width == 50)
        expect(c.selectedImage()?.height == 30)
    }

    static func test_beautifyAddsPadding() {
        let source = image(width: 100, height: 60)
        let out = Beautifier.apply(source, scale: 1)
        let pad = Beautifier.paddings[AppSettings.shared.beautifyPadding]
        expect(out.width == 100 + Int(pad * 2))
        expect(out.height == 60 + Int(pad * 2))
    }
}

@MainActor
enum SelfTest_KeyTests {
    static func expect(_ c: @autoclosure () throws -> Bool, _ m: String = "", line: Int = #line) { SelfTest.expect(try c(), m, line: line) }
    static func require<T>(_ v: T?) throws -> T { guard let v else { throw SelfTest.Missing() }; return v }

    static func test_versionComparison() {
        expect(UpdateChecker.isNewer("0.10.0", than: "0.9.1"))
        expect(UpdateChecker.isNewer("0.3", than: "0.2.9"))
        expect(!UpdateChecker.isNewer("0.2.0", than: "0.2"))
        expect(!UpdateChecker.isNewer("0.1.9", than: "0.2.0"))
    }

    private static func key(_ chars: String, code: Int, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
    }

    static func test_latinLetters() {
        expect(KeyLetter.of(key("t", code: kVK_ANSI_T, flags: .command)) == "t")
        expect(KeyLetter.of(key("R", code: kVK_ANSI_R)) == "r")
    }

    static func test_koreanInputMapsToKeyLetter() {
        // 한글 입력 상태에서 R 자리를 누르면 'ㄱ'이 들어온다.
        expect(KeyLetter.of(key("ㄱ", code: kVK_ANSI_R)) == "r")
        expect(KeyLetter.of(key("ㅅ", code: kVK_ANSI_T, flags: .command)) == "t")
        expect(Tool.forLetter(KeyLetter.of(key("ㅍ", code: kVK_ANSI_V))) == .select)
    }

    static func test_questionMarkAndSlash() {
        expect(KeyLetter.of(key("?", code: kVK_ANSI_Slash, flags: .shift)) == "/")
        expect(KeyLetter.of(key("/", code: kVK_ANSI_Slash)) == "/")
    }

    static func test_fallsBackToKeyPosition() {
        expect(KeyLetter.of(key("", code: kVK_ANSI_C)) == "c")
    }

    static func test_everyToolHasAShortcut() {
        for tool in Tool.allCases {
            let letters: [Tool: Character] = [.select: "v", .arrow: "a", .line: "l", .rect: "r", .ellipse: "o", .pen: "p",
                                              .text: "t", .step: "n", .highlight: "h", .mosaic: "m", .blur: "b"]
            expect(Tool.forLetter(letters[tool]) == tool)
            expect(Tool(key: tool.key) == tool)
        }
    }

    static func test_systemScreenshotShortcutsAreRejected() {
        let shiftCommand = UInt32(shiftKey | cmdKey)
        expect(HotKeyConflicts.systemShortcut(KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: shiftCommand, key: "4")) == "⇧⌘4")
        expect(HotKeyConflicts.systemShortcut(KeyCombo.defaults[HotKeyAction.captureArea.rawValue]!) == nil)
        // 기본값 ⇧⌘3·⇧⌘4는 macOS 단축키와 같다는 걸 알아채야 한다(끄도록 안내하려고).
        expect(HotKeyConflicts.systemShortcut(KeyCombo.defaults[HotKeyAction.captureFullScreen.rawValue]!) == "⇧⌘3")
        expect(HotKeyConflicts.systemShortcut(KeyCombo.defaults[HotKeyAction.captureWindow.rawValue]!) == "⇧⌘4")
    }

    static func test_defaultShortcutsDoNotCollide() {
        let combos = Array(KeyCombo.defaults.values)
        expect(Set(combos.map { "\($0.keyCode)-\($0.modifiers)" }).count == combos.count)
        expect(KeyCombo.defaults.count == HotKeyAction.allCases.count)
    }

    static func test_displayText() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(controlKey | cmdKey), key: "`")
        expect(combo.displayText == "⌃⌘₩")
    }
}

@MainActor
enum SelfTest_StoreTests {
    static func expect(_ c: @autoclosure () throws -> Bool, _ m: String = "", line: Int = #line) { SelfTest.expect(try c(), m, line: line) }
    static func require<T>(_ v: T?) throws -> T { guard let v else { throw SelfTest.Missing() }; return v }

    private static func tempStore() -> (CaptureStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GrabbyTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (CaptureStore(directory: dir), dir)
    }

    private static var image: CGImage { ScreenShot.white(width: 20, height: 10)! }

    static func test_pruneKeepsNewestAndKept() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        for _ in 0..<5 { store.add(image, scale: 1) }
        let oldest = store.items.last!
        store.setKept(oldest, true)
        let removed = store.prune(limit: 2)
        store.flush()
        expect(removed == 2)
        // 고정한 가장 오래된 것 + 최신 2개
        expect(store.items.count == 3)
        expect(store.items.contains { $0.id == oldest.id })
        // 남은 캡처의 파일은 있고, 정리된 캡처의 파일은 지워져야 한다.
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }) ?? []
        expect(files.count == 3, "png \(files.count)개")
    }

    static func test_removeAllKeepsKeptWhenAsked() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        for _ in 0..<3 { store.add(image, scale: 1) }
        store.setKept(store.items[1], true)
        expect(store.removeAll(keepKept: true) == 2)
        expect(store.items.count == 1)
        expect(store.removeAll(keepKept: false) == 1)
        expect(store.items.isEmpty)
    }

    static func test_editableKeepsOriginalAndMarks() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marks: [Annotation] = [.rect(CGRect(x: 1, y: 1, width: 5, height: 5), color: .systemRed, width: 2)]
        let (item, _) = store.add(image, scale: 1, original: image, annotations: marks)
        let editable = try require(store.editable(for: item))
        expect(editable.annotations.count == 1)
        // 표시 없이 다시 저장하면 원본·표시 파일을 지운다.
        store.replace(item, with: image)
        expect(store.editable(for: item)?.annotations.isEmpty == true)
    }

    static func test_reloadsFromDisk() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (item, _) = store.add(image, scale: 2)
        store.setNote(item, "  회의 자료  ")
        store.flush()
        let reopened = CaptureStore(directory: dir)
        expect(reopened.items.count == 1)
        expect(reopened.items[0].note == "회의 자료")
        expect(reopened.items[0].scale == 2)
    }

    static func test_oldIndexWithoutNewFieldsStillLoads() throws {
        let old = #"[{"id":"7B839A86-0000-0000-0000-000000000000","date":0,"width":10,"height":5,"scale":2}]"#
        let items = try JSONDecoder().decode([CaptureItem].self, from: Data(old.utf8))
        expect(items[0].isKept == false && items[0].note == nil && items[0].text == nil)
    }

    static func test_searchMatchesNoteAndText() {
        var item = CaptureItem(id: UUID(), date: Date(), width: 1, height: 1, scale: 1)
        item.note = "버그 화면"
        item.text = "Error 404 Not Found"
        expect(item.matches("버그"))
        expect(item.matches("not found"))
        expect(item.matches(""))
        expect(!item.matches("회의"))
    }
}
