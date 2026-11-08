import AppKit
import Carbon

/// 캡처를 마친 뒤 할 일.
enum CaptureAction {
    case copy, save, pin, ocr, beautify
}

/// 영역 캡처를 마친 결과. `rect`는 화면 왼쪽 위 기준 포인트 좌표다.
struct CaptureResult {
    /// 표시를 합친 이미지
    let image: CGImage
    /// 표시가 있을 때 표시 없는 원본(탭에서 다시 고칠 수 있게 함께 저장한다)
    var original: CGImage? = nil
    var annotations: [Annotation] = []
    let pixelScale: CGFloat
    let rect: CGRect
    let displayID: CGDirectDisplayID
    /// 이 화면의 전역 좌표(왼쪽 아래 원점). 핀과 깜빡임 위치를 잡을 때 쓴다.
    let screenFrame: CGRect
    /// 화이트보드 결과는 화면을 찍은 게 아니므로 '마지막 영역'으로 기억하지 않는다.
    var isWhiteboard = false
    var action: CaptureAction = .copy

    /// 캡처한 영역의 전역 좌표(왼쪽 아래 원점).
    var globalRect: CGRect {
        CGRect(x: screenFrame.minX + rect.minX, y: screenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// 멈춘 화면들을 덮어 영역을 고르고, 고른 자리에서 바로 편집하게 한다.
/// 창은 포커스를 빼앗지 않는 패널이라, 원래 앱은 그대로 앞에 있고 키 입력만 이쪽으로 온다.
final class CaptureSession {
    enum Mode { case area, fullScreen, whiteboard }

    private var windows: [OverlayWindow] = []
    private let completion: (CaptureResult?) -> Void
    private var finished = false
    let mode: Mode

    init(shots: [ScreenShot], mode: Mode = .area, completion: @escaping (CaptureResult?) -> Void) {
        self.completion = completion
        self.mode = mode
        windows = shots.map { OverlayWindow(shot: $0, session: self, blank: mode == .whiteboard) }
        let mouse = NSEvent.mouseLocation
        for window in windows { window.orderFrontRegardless() }
        // 마우스가 있는 화면이 키 입력을 받게 한다.
        let active = windows.first { $0.frame.contains(mouse) } ?? windows.first
        active?.makeKey()
        guard let overlay = active?.overlay else { return }
        switch mode {
        case .area:
            overlay.pointerMoved(to: overlay.convert(active!.convertPoint(fromScreen: mouse), from: nil))
        case .fullScreen:
            overlay.presentFullScreen()
        case .whiteboard:
            let size = overlay.bounds.size
            let board = CGSize(width: min(1200, size.width * 0.8), height: min(800, size.height * 0.75))
            overlay.preselect(CGRect(x: (size.width - board.width) / 2, y: (size.height - board.height) / 2,
                                     width: board.width, height: board.height), tool: AppSettings.shared.whiteboardTool)
        }
    }

    /// 한 화면에서 새로 영역을 고르기 시작하면 다른 화면의 선택은 지운다.
    fileprivate func beginSelection(on window: OverlayWindow) {
        for other in windows where other !== window { other.overlay.reset() }
        if !window.isKeyWindow { window.makeKey() }
    }

    fileprivate func confirm(_ overlay: OverlayView, _ action: CaptureAction = .copy) {
        guard let canvas = overlay.canvas, let rect = overlay.selection else { return }
        let frame = overlay.shot.screen.frame
        let isBoard = mode == .whiteboard
        // 영역 안에서 일부를 다시 골랐으면 그 부분만 쓴다.
        if let part = canvas.selectedImage(), let sub = canvas.selectionRect {
            let annotations = canvas.annotations.map { $0.offsetBy(dx: -sub.minX, dy: -sub.minY) }
            finish(CaptureResult(image: part, original: annotations.isEmpty ? nil : canvas.selectedOriginal(), annotations: annotations,
                                 pixelScale: canvas.pixelScale, rect: sub.offsetBy(dx: rect.minX, dy: rect.minY),
                                 displayID: overlay.shot.displayID, screenFrame: frame, isWhiteboard: isBoard, action: action))
            return
        }
        let annotations = canvas.annotations
        finish(CaptureResult(image: canvas.render(), original: annotations.isEmpty ? nil : canvas.image, annotations: annotations,
                             pixelScale: canvas.pixelScale, rect: rect, displayID: overlay.shot.displayID, screenFrame: frame,
                             isWhiteboard: isBoard, action: action))
    }

    fileprivate func cancel() { finish(nil) }

    private func finish(_ result: CaptureResult?) {
        guard !finished else { return }
        finished = true
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        completion(result)
    }
}

final class OverlayWindow: NSPanel {
    let overlay: OverlayView
    private weak var session: CaptureSession?

    init(shot: ScreenShot, session: CaptureSession, blank: Bool) {
        overlay = OverlayView(shot: shot, blank: blank)
        self.session = session
        super.init(contentRect: shot.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlay.session = session
        contentView = overlay
        setFrame(shot.screen.frame, display: false)
        makeFirstResponder(overlay)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if handleCommand(event) { return }
        let canvas = overlay.canvas
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        switch Int(event.keyCode) {
        case kVK_Escape:
            // 고른 표시나 부분 선택이 있으면 그것만 푼다.
            if canvas?.clearSelections() != true { session?.cancel() }
        case kVK_Return, kVK_ANSI_KeypadEnter:
            session?.confirm(overlay)
        case kVK_Delete, kVK_ForwardDelete:
            canvas?.deleteSelected()
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let code = Int(event.keyCode)
            let dx = code == kVK_LeftArrow ? -step : code == kVK_RightArrow ? step : 0
            let dy = code == kVK_UpArrow ? -step : code == kVK_DownArrow ? step : 0
            overlay.nudge(dx: dx, dy: dy, resize: event.modifierFlags.contains(.option))
        case _ where canvas == nil && plain && KeyLetter.of(event) == "c":
            overlay.copyColorUnderPointer()
            session?.cancel()
        case _ where KeyLetter.of(event) == "/":
            overlay.toggleHelp()
        case _ where canvas == nil && plain && KeyLetter.of(event) == "f":
            overlay.presentFullScreen()
        default:
            if let canvas, plain, let tool = Tool.forLetter(KeyLetter.of(event)) {
                canvas.tool = tool
                invalidateCursorRects(for: canvas)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// 앱이 앞에 있지 않아도 동작하도록 ⌘ 단축키를 직접 받는다. 글자를 입력하는 중에는 입력 칸에 넘긴다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        return handleCommand(event) || super.performKeyEquivalent(with: event)
    }

    /// ⌘ 조합을 처리했으면 true. 키 이벤트가 performKeyEquivalent를 거치지 않고 keyDown으로 오는 경우에도 쓴다.
    private func handleCommand(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods.contains(.command), overlay.canvas?.isEditingText != true else { return false }
        switch KeyLetter.of(event) {
        case "c" where mods == .command: session?.confirm(overlay, .copy)
        case "s" where mods == .command: session?.confirm(overlay, .save)
        case "p" where mods == .command: session?.confirm(overlay, .pin)
        case "t" where mods == .command: session?.confirm(overlay, .ocr)
        case "b" where mods == .command: session?.confirm(overlay, .beautify)
        case "z": mods.contains(.shift) ? overlay.canvas?.redo() : overlay.canvas?.undo()
        default: return false
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) { session?.cancel() }
}

final class OverlayView: NSView {
    let shot: ScreenShot
    weak var session: CaptureSession?
    private(set) var selection: CGRect?
    private(set) var canvas: AnnotationCanvas?
    private var toolbar: EditToolbar?
    private var handles: HandlesView?
    private var dragStart: CGPoint?
    /// 화이트보드: 고른 영역을 화면 대신 바탕 이미지로 채운다.
    private let blank: Bool
    /// 손잡이를 끌어 영역 크기를 조정하는 중이면 그 손잡이.
    private var resizing: Handle?
    /// 마우스 아래의 창. 드래그하지 않고 클릭하면 이 창 영역을 고른다.
    private var hoveredWindow: CGRect?
    private var windowRects: [CGRect] = []
    private let loupe = LoupeView()
    /// 전체 화면 캡처: 화면 전체를 조금 줄여 가운데에 보여 준다. 영역 손잡이는 쓰지 않는다.
    private var isPreview = false
    private var help: NSView?

    /// ?: 모든 단축키를 화면 가운데에 보여 주거나 숨긴다.
    func toggleHelp() {
        if let help {
            help.removeFromSuperview()
            self.help = nil
            return
        }
        let panel = HelpPanel.make()
        panel.setFrameOrigin(CGPoint(x: ((bounds.width - panel.frame.width) / 2).rounded(),
                                     y: ((bounds.height - panel.frame.height) / 2).rounded()))
        addSubview(panel)
        help = panel
    }

    init(shot: ScreenShot, blank: Bool) {
        self.shot = shot
        self.blank = blank
        super.init(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
        wantsLayer = true
        if !blank { windowRects = WindowList.rects(on: shot.displayID) }
        loupe.isHidden = true
        addSubview(loupe)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func reset() {
        canvas?.removeFromSuperview()
        toolbar?.removeFromSuperview()
        handles?.removeFromSuperview()
        canvas = nil
        toolbar = nil
        handles = nil
        resizing = nil
        selection = nil
        dragStart = nil
        isPreview = false
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    /// 손잡이를 쓸 수 있는 영역(전체 화면 미리 보기에서는 없다).
    private var handleRect: CGRect? { isPreview ? nil : selection }

    /// 영역을 고르는 동안은 십자, 편집 중에는 영역 밖에서 일반 화살표를 보여 준다(영역 안은 캔버스가 정한다).
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: canvas == nil ? .crosshair : .arrow)
        guard canvas != nil, let selection = handleRect else { return }
        for handle in Handle.allCases { addCursorRect(handle.hitRect(in: selection), cursor: handle.cursor) }
    }

    /// 손잡이는 캔버스 위에 걸쳐 있으므로 캔버스보다 먼저 클릭을 받는다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if canvas != nil, let selection = handleRect, let superview {
            let p = convert(point, from: superview)
            if Handle.allCases.contains(where: { $0.hitRect(in: selection).contains(p) }) { return self }
        }
        let hit = super.hitTest(point)
        return hit === loupe ? self : hit
    }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: shot.image, size: bounds.size)
            .draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        // 전체 화면 미리 보기는 바탕을 더 어둡게 해서 줄인 화면이 눈에 띄게 한다.
        if isPreview {
            NSColor.black.withAlphaComponent(0.6).setFill()
            bounds.fill(using: .sourceOver)
            return
        }
        // 아직 고르기 전이면 마우스 아래 창을 밝게 보여 준다.
        let hole = selection ?? (dragStart == nil ? hoveredWindow : nil)
        let dim = NSBezierPath(rect: bounds)
        if let hole { dim.append(NSBezierPath(rect: hole)) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

        if selection == nil, dragStart == nil, let hoveredWindow {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: hoveredWindow.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
            drawSizeLabel(for: hoveredWindow)
            return
        }
        guard let selection else { return }
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
        if canvas == nil || resizing != nil { drawSizeLabel(for: selection) }
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width * shot.scale)) × \(Int(rect.height * shot.scale))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var box = CGRect(x: rect.minX, y: rect.minY - size.height - 8, width: size.width + 10, height: size.height + 4)
        if box.minY < 0 { box.origin.y = rect.minY + 4; box.origin.x = rect.minX + 4 }
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: box.minX + 5, y: box.minY + 2), withAttributes: attributes)
    }

    // MARK: 돋보기와 마우스 아래 창

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        loupe.isHidden = true
    }

    /// 앱이 앞에 있지 않으면 커서 영역이 동작하지 않을 수 있어 직접 커서를 정한다.
    func pointerMoved(to p: CGPoint) {
        guard let canvas else {
            NSCursor.crosshair.set()
            showLoupe(at: p)
            let window = dragStart == nil ? windowRects.first { $0.contains(p) } : nil
            if window != hoveredWindow {
                hoveredWindow = window
                needsDisplay = true
            }
            return
        }
        loupe.isHidden = true
        if let selection = handleRect, let handle = Handle.allCases.first(where: { $0.hitRect(in: selection).contains(p) }) {
            handle.cursor.set()
        } else if canvas.frame.contains(p), toolbar?.frame.contains(p) != true {
            (canvas.tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func showLoupe(at p: CGPoint) {
        loupe.isHidden = false
        loupe.update(shot: shot, point: p)
        let size = loupe.frame.size, gap: CGFloat = 24
        var origin = CGPoint(x: p.x + gap, y: p.y + gap)
        if origin.x + size.width > bounds.width { origin.x = p.x - gap - size.width }
        if origin.y + size.height > bounds.height { origin.y = p.y - gap - size.height }
        loupe.setFrameOrigin(origin)
    }

    /// C: 돋보기 가운데 픽셀 색을 #RRGGBB로 복사한다.
    func copyColorUnderPointer() {
        guard let hex = loupe.hex else { return }
        Clipboard.copy(text: hex)
        Toast.show(L("색을 복사했어요 · %@", hex), image: loupe.swatch)
    }

    // MARK: 영역 선택

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if canvas != nil, let selection = handleRect, let handle = Handle.allCases.first(where: { $0.hitRect(in: selection).contains(p) }) {
            resizing = handle
            return
        }
        // 표시를 그린 뒤에는 바깥을 눌러도 선택을 버리지 않는다.
        if let canvas, canvas.hasEdits { return }
        reset()
        session?.beginSelection(on: window as! OverlayWindow)
        dragStart = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let resizing, let selection {
            applySelection(resizing.resize(selection, to: p))
            return
        }
        guard let start = dragStart else { return }
        let x = min(max(p.x, 0), bounds.width), y = min(max(p.y, 0), bounds.height)
        selection = CGRect(x: min(start.x, x), y: min(start.y, y), width: abs(x - start.x), height: abs(y - start.y)).integral
        showLoupe(at: CGPoint(x: x, y: y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if resizing != nil {
            resizing = nil
            needsDisplay = true
            return
        }
        guard let start = dragStart else { return }
        dragStart = nil
        if let selection, selection.width >= 4, selection.height >= 4 {
            beginEditing(selection)
            return
        }
        // 드래그하지 않고 클릭했으면 그 자리의 창을 고른다.
        if let window = windowRects.first(where: { $0.contains(start) }) {
            selection = window
            beginEditing(window)
            return
        }
        reset()
    }

    /// `frame`을 주면 캔버스를 그 자리에 놓는다(전체 화면 미리 보기). 없으면 고른 영역 그대로.
    private func beginEditing(_ rect: CGRect, frame: CGRect? = nil) {
        guard let image = content(for: rect) else { reset(); return }
        loupe.isHidden = true
        hoveredWindow = nil
        let canvas = AnnotationCanvas(image: image, pixelScale: shot.scale)
        canvas.frame = frame ?? rect
        addSubview(canvas, positioned: .below, relativeTo: loupe)
        self.canvas = canvas

        canvas.tool = AppSettings.shared.captureTool
        let toolbar = EditToolbar(canvas: canvas, tools: Tool.allCases, actions: [
            .init(symbol: "xmark", title: L("취소 (Esc)")) { [weak self] in self?.session?.cancel() },
            .init(symbol: "pin", title: L("화면에 띄우기 (⌘P) · 복사하고 탭에도 추가")) { [weak self] in
                guard let self else { return }
                self.session?.confirm(self, .pin)
            },
            .init(symbol: "text.viewfinder", title: L("글자 복사 (⌘T) · 이미지 속 글자를 인식해 복사")) { [weak self] in
                guard let self else { return }
                self.session?.confirm(self, .ocr)
            },
            .init(symbol: "wand.and.stars", title: L("꾸며서 복사 (⌘B) · 여백·배경·그림자를 넣어 복사")) { [weak self] in
                guard let self else { return }
                self.session?.confirm(self, .beautify)
            },
            .init(symbol: "square.and.arrow.down", title: L("파일로 저장 (⌘S) · 복사하고 탭에도 추가")) { [weak self] in
                guard let self else { return }
                self.session?.confirm(self, .save)
            },
            .init(symbol: "checkmark", title: L("복사하고 탭에 추가 (↩ 또는 ⌘C)"), label: L("완료"), isPrimary: true) { [weak self] in
                guard let self else { return }
                self.session?.confirm(self)
            },
        ], hint: L("안에서 드래그해 일부만 고르기 · 그린 표시는 눌러서 옮기기·⌫ 지우기 · ↩/⌘C 복사 · Esc 취소 · ? 단축키 도움말"))
        addSubview(toolbar, positioned: .below, relativeTo: loupe)
        self.toolbar = toolbar
        if !isPreview {
            let handles = HandlesView()
            addSubview(handles, positioned: .below, relativeTo: loupe)
            self.handles = handles
        }
        layoutChrome()
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    /// 캔버스에 놓을 이미지: 화면에서 잘라낸 부분, 화이트보드면 같은 크기의 바탕.
    private func content(for rect: CGRect) -> CGImage? {
        guard blank else { return shot.crop(rect) }
        return ScreenShot.board(AppSettings.shared.boardStyle, width: Int(rect.width * shot.scale),
                                height: Int(rect.height * shot.scale), scale: shot.scale)
    }

    /// 전체 화면을 고르되, 화면 전체를 조금 줄여 가운데에 보여 주고 그 위에서 편집한다.
    /// 아래쪽에는 도구 막대 자리를 남긴다.
    func presentFullScreen() {
        reset()
        let available = CGRect(x: 48, y: 40, width: bounds.width - 96, height: bounds.height - 40 - 120)
        let scale = min(available.width / bounds.width, available.height / bounds.height, 0.9)
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        let frame = CGRect(x: ((bounds.width - size.width) / 2).rounded(), y: available.minY + ((available.height - size.height) / 2).rounded(),
                           width: size.width, height: size.height)
        isPreview = true
        selection = bounds
        beginEditing(bounds, frame: frame)
        canvas?.wantsLayer = true
        canvas?.shadow = {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 24
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            return shadow
        }()
    }

    /// 영역을 미리 고른 채 편집을 시작한다(화이트보드).
    func preselect(_ rect: CGRect, tool: Tool) {
        reset()
        let rect = rect.intersection(bounds).integral
        guard rect.width >= 4, rect.height >= 4 else { return }
        selection = rect
        beginEditing(rect)
        canvas?.tool = tool
    }

    /// 편집 중에 영역을 바꾼다. 그린 표시는 화면에서 같은 자리에 남는다.
    func applySelection(_ rect: CGRect) {
        guard let canvas, let old = selection else { return }
        let rect = rect.intersection(bounds).integral
        guard rect.width >= 4, rect.height >= 4, rect != old, let image = content(for: rect) else { return }
        selection = rect
        canvas.frame = rect
        canvas.recrop(image, originShift: CGPoint(x: rect.minX - old.minX, y: rect.minY - old.minY))
        layoutChrome()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    /// 방향키: 영역을 옮긴다. ⌥를 누르면 오른쪽·아래 변을 움직여 크기를 바꾼다.
    func nudge(dx: CGFloat, dy: CGFloat, resize: Bool) {
        guard canvas != nil, let selection = handleRect else { return }
        if resize {
            applySelection(CGRect(x: selection.minX, y: selection.minY, width: selection.width + dx, height: selection.height + dy))
        } else {
            var moved = selection.offsetBy(dx: dx, dy: dy)
            moved.origin.x = min(max(moved.minX, 0), bounds.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), bounds.height - moved.height)
            applySelection(moved)
        }
    }

    /// 손잡이와 도구 막대를 영역에 맞춰 놓는다.
    private func layoutChrome() {
        guard let rect = isPreview ? canvas?.frame : selection else { return }
        handles?.frame = rect.insetBy(dx: -Handle.size, dy: -Handle.size)
        handles?.needsDisplay = true
        guard let toolbar else { return }
        // 선택 영역 아래 오른쪽에 붙이고, 자리가 없으면 위, 그래도 없으면 안쪽 아래에 둔다.
        let size = toolbar.frame.size, gap: CGFloat = 10
        var origin = CGPoint(x: rect.maxX - size.width, y: rect.maxY + gap)
        if origin.y + size.height > bounds.height {
            origin.y = rect.minY - gap - size.height
            if origin.y < 0 { origin.y = rect.maxY - gap - size.height }
        }
        origin.x = min(max(origin.x, gap), bounds.width - size.width - gap)
        toolbar.setFrameOrigin(origin)
    }
}

/// 커서 주변을 크게 보여 주는 돋보기. 가운데 픽셀의 좌표와 색도 보여 준다.
final class LoupeView: NSView {
    private static let pixels = 15
    private static let zoomSide: CGFloat = 135
    private static let labelHeight: CGFloat = 34
    private var zoomed: CGImage?
    private var label = ""
    private(set) var hex: String?
    private var centerColor: NSColor?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.zoomSide, height: Self.zoomSide + Self.labelHeight))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var swatch: NSImage? {
        guard let centerColor else { return nil }
        return NSImage(size: NSSize(width: 36, height: 36), flipped: false) { rect in
            centerColor.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
            return true
        }
    }

    func update(shot: ScreenShot, point p: CGPoint) {
        let n = Self.pixels, half = n / 2
        let px = Int(p.x * shot.scale), py = Int(p.y * shot.scale)
        let region = CGRect(x: px - half, y: py - half, width: n, height: n)
        let imageRect = CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height)
        let visible = region.intersection(imageRect)
        guard let context = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: n, height: n))
        if !visible.isNull, let piece = shot.image.cropping(to: visible) {
            // 위쪽 기준 오프셋을 아래쪽 기준 그리기 좌표로 바꾼다.
            let ox = visible.minX - region.minX, oy = visible.minY - region.minY
            context.interpolationQuality = .none
            context.draw(piece, in: CGRect(x: ox, y: CGFloat(n) - oy - visible.height, width: visible.width, height: visible.height))
        }
        zoomed = context.makeImage()
        // 메모리의 첫 줄이 위쪽이므로 가운데 픽셀은 (half, half) 자리다.
        if let data = context.data?.assumingMemoryBound(to: UInt8.self) {
            let offset = (half * n + half) * 4
            let r = data[offset], g = data[offset + 1], b = data[offset + 2]
            hex = String(format: "#%02X%02X%02X", r, g, b)
            centerColor = NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
        label = "\(Int(p.x)), \(Int(p.y))   \(hex ?? "")"
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = Self.zoomSide
        if let zoomed {
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: zoomed, size: NSSize(width: side, height: side))
                .draw(in: CGRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1,
                      respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        }
        // 가운데 픽셀 표시
        let cell = side / CGFloat(Self.pixels)
        let center = CGRect(x: cell * CGFloat(Self.pixels / 2), y: cell * CGFloat(Self.pixels / 2), width: cell, height: cell)
        NSColor.black.setStroke()
        NSBezierPath(rect: center.insetBy(dx: -1, dy: -1)).stroke()
        NSColor.white.setStroke()
        NSBezierPath(rect: center).stroke()

        let info = CGRect(x: 0, y: side, width: side, height: Self.labelHeight)
        NSColor.black.withAlphaComponent(0.8).setFill()
        info.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white,
        ]
        (label as NSString).draw(at: CGPoint(x: 6, y: side + 3), withAttributes: attributes)
        let hint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.white.withAlphaComponent(0.7)]
        (L("C 색 복사 · F 전체 화면 · 클릭 창 · ? 도움말") as NSString).draw(at: CGPoint(x: 6, y: side + 18), withAttributes: hint)
    }
}

/// 캡처 중 ?를 누르면 뜨는 단축키 도움말.
enum HelpPanel {
    static func make() -> NSView {
        let sections: [(String, [(String, String)])] = [
            (L("영역 고르기"), [
                (L("드래그"), L("영역 고르기")), (L("클릭"), L("마우스 아래 창 고르기")),
                ("F", L("전체 화면")), ("C", L("가운데 픽셀 색 복사")), ("Esc", L("취소")),
            ]),
            (L("편집"), [
                ("V A L R O P", L("부분 선택 · 화살표 · 직선 · 네모 · 동그라미 · 자유그리기")),
                ("T N H M B", L("텍스트 · 번호 · 형광펜 · 모자이크 · 흐리게")),
                (L("표시 클릭"), L("고르기 · 끌어서 옮기기 · ⌫ 지우기 · 더블클릭 텍스트 고치기")),
                ("⇧", L("화살표·직선 45도, 네모·동그라미 정사각형")),
                ("⌘Z  ⇧⌘Z", L("되돌리기 · 다시 실행")),
                (L("방향키"), L("영역 옮기기 (⇧ 10px, ⌥ 크기)")),
            ]),
            (L("마치기"), [
                ("↩  ⌘C", L("복사하고 탭에 추가")), ("⌘S", L("파일로 저장")), ("⌘P", L("화면에 띄우기")),
                ("⌘T", L("글자 복사")), ("⌘B", L("꾸며서 복사")),
            ]),
        ]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        for (title, rows) in sections {
            let header = NSTextField(labelWithString: title)
            header.font = .boldSystemFont(ofSize: 13)
            header.textColor = .white
            if stack.arrangedSubviews.count > 0 { stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!) }
            stack.addArrangedSubview(header)
            for (key, meaning) in rows {
                let keyLabel = NSTextField(labelWithString: key)
                keyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
                keyLabel.textColor = .white
                keyLabel.widthAnchor.constraint(equalToConstant: 110).isActive = true
                let meaningLabel = NSTextField(labelWithString: meaning)
                meaningLabel.font = .systemFont(ofSize: 12)
                meaningLabel.textColor = NSColor.white.withAlphaComponent(0.85)
                stack.addArrangedSubview(NSStackView(views: [keyLabel, meaningLabel]))
            }
        }
        let footer = NSTextField(labelWithString: L("?를 다시 누르면 닫혀요"))
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = NSColor.white.withAlphaComponent(0.6)
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(footer)

        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        background.layer?.cornerRadius = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        background.setFrameSize(stack.fittingSize)
        return background
    }
}

/// 영역 테두리의 손잡이 8개. x, y는 -1(왼쪽·위), 0(가운데), 1(오른쪽·아래).
enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    static let size: CGFloat = 8

    var x: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: return -1
        case .top, .bottom: return 0
        case .topRight, .right, .bottomRight: return 1
        }
    }

    var y: Int {
        switch self {
        case .topLeft, .top, .topRight: return -1
        case .left, .right: return 0
        case .bottomLeft, .bottom, .bottomRight: return 1
        }
    }

    var cursor: NSCursor { x == 0 ? .resizeUpDown : y == 0 ? .resizeLeftRight : .crosshair }

    func center(in r: CGRect) -> CGPoint {
        CGPoint(x: x < 0 ? r.minX : x > 0 ? r.maxX : r.midX, y: y < 0 ? r.minY : y > 0 ? r.maxY : r.midY)
    }

    /// 잡기 쉽게 그려지는 크기보다 넓게 받는다.
    func hitRect(in r: CGRect) -> CGRect {
        let c = center(in: r), hit: CGFloat = 16
        return CGRect(x: c.x - hit / 2, y: c.y - hit / 2, width: hit, height: hit)
    }

    func resize(_ r: CGRect, to p: CGPoint) -> CGRect {
        let minSide: CGFloat = 8
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        if x < 0 { minX = min(p.x, maxX - minSide) }
        if x > 0 { maxX = max(p.x, minX + minSide) }
        if y < 0 { minY = min(p.y, maxY - minSide) }
        if y > 0 { maxY = max(p.y, minY + minSide) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// 캔버스 위에 테두리와 손잡이를 그린다. 클릭은 받지 않는다(OverlayView가 받는다).
final class HandlesView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let inner = bounds.insetBy(dx: Handle.size, dy: Handle.size)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: inner.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
        for handle in Handle.allCases {
            let c = handle.center(in: inner), s = Handle.size
            let box = NSBezierPath(roundedRect: CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s), xRadius: 2, yRadius: 2)
            NSColor.white.setFill()
            box.fill()
            NSColor.black.withAlphaComponent(0.5).setStroke()
            box.lineWidth = 1
            box.stroke()
        }
    }
}



