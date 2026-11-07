import AppKit
import Carbon

/// 영역 캡처를 마친 결과. `rect`는 화면 왼쪽 위 기준 포인트 좌표다.
struct CaptureResult {
    let image: CGImage
    let pixelScale: CGFloat
    let rect: CGRect
    let displayID: CGDirectDisplayID
    /// 화이트보드 결과는 화면을 찍은 게 아니므로 '마지막 영역'으로 기억하지 않는다.
    var isWhiteboard = false
}

/// 멈춘 화면들을 덮어 영역을 고르고, 고른 자리에서 바로 편집하게 한다.
final class CaptureSession {
    private var windows: [OverlayWindow] = []
    private let completion: (CaptureResult?) -> Void
    private var finished = false
    private let isWhiteboard: Bool

    /// `whiteboard`이면 첫 화면의 가운데 영역을 미리 골라 둔 채 자유그리기로 시작한다.
    init(shots: [ScreenShot], whiteboard: Bool = false, completion: @escaping (CaptureResult?) -> Void) {
        self.completion = completion
        isWhiteboard = whiteboard
        windows = shots.map { OverlayWindow(shot: $0, session: self) }
        let mouse = NSEvent.mouseLocation
        for window in windows { window.orderFrontRegardless() }
        // 마우스가 있는 화면이 키 입력을 받게 한다.
        let active = windows.first { $0.frame.contains(mouse) } ?? windows.first
        active?.makeKeyAndOrderFront(nil)
        if whiteboard, let overlay = active?.overlay {
            let size = overlay.bounds.size
            let board = CGSize(width: min(1200, size.width * 0.8), height: min(800, size.height * 0.75))
            overlay.preselect(CGRect(x: (size.width - board.width) / 2, y: (size.height - board.height) / 2,
                                     width: board.width, height: board.height), tool: .pen)
        }
    }

    /// 한 화면에서 새로 영역을 고르기 시작하면 다른 화면의 선택은 지운다.
    fileprivate func beginSelection(on window: OverlayWindow) {
        for other in windows where other !== window { other.overlay.reset() }
        if !window.isKeyWindow { window.makeKey() }
    }

    fileprivate func confirm(_ overlay: OverlayView) {
        guard let canvas = overlay.canvas, let rect = overlay.selection else { return }
        finish(CaptureResult(image: canvas.render(), pixelScale: canvas.pixelScale, rect: rect, displayID: overlay.shot.displayID,
                             isWhiteboard: isWhiteboard))
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

final class OverlayWindow: NSWindow {
    let overlay: OverlayView
    private weak var session: CaptureSession?

    init(shot: ScreenShot, session: CaptureSession) {
        overlay = OverlayView(shot: shot)
        self.session = session
        super.init(contentRect: shot.screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlay.session = session
        contentView = overlay
        setFrame(shot.screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        let canvas = overlay.canvas
        switch Int(event.keyCode) {
        case kVK_Escape:
            session?.cancel()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            session?.confirm(overlay)
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let code = Int(event.keyCode)
            let dx = code == kVK_LeftArrow ? -step : code == kVK_RightArrow ? step : 0
            let dy = code == kVK_UpArrow ? -step : code == kVK_DownArrow ? step : 0
            overlay.nudge(dx: dx, dy: dy, resize: event.modifierFlags.contains(.option))
        default:
            if let canvas, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               let tool = Tool.forKeyCode(event.keyCode) {
                canvas.tool = tool
                invalidateCursorRects(for: canvas)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    @objc func copy(_ sender: Any?) { session?.confirm(overlay) }
    @objc func undo(_ sender: Any?) { overlay.canvas?.undo() }
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
    /// 손잡이를 끌어 영역 크기를 조정하는 중이면 그 손잡이.
    private var resizing: Handle?

    init(shot: ScreenShot) {
        self.shot = shot
        super.init(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
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
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    /// 영역을 고르는 동안은 십자, 편집 중에는 영역 밖에서 일반 화살표를 보여 준다(영역 안은 캔버스가 정한다).
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: canvas == nil ? .crosshair : .arrow)
        guard canvas != nil, let selection else { return }
        for handle in Handle.allCases {
            let cursor: NSCursor = handle.x == 0 ? .resizeUpDown : handle.y == 0 ? .resizeLeftRight : .crosshair
            addCursorRect(handle.hitRect(in: selection), cursor: cursor)
        }
    }

    /// 손잡이는 캔버스 위에 걸쳐 있으므로 캔버스보다 먼저 클릭을 받는다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if canvas != nil, let selection, let superview {
            let p = convert(point, from: superview)
            if Handle.allCases.contains(where: { $0.hitRect(in: selection).contains(p) }) { return self }
        }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: shot.image, size: bounds.size)
            .draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        let dim = NSBezierPath(rect: bounds)
        if let selection { dim.append(NSBezierPath(rect: selection)) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

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

    // MARK: 영역 선택

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if canvas != nil, let selection, let handle = Handle.allCases.first(where: { $0.hitRect(in: selection).contains(p) }) {
            resizing = handle
            return
        }
        // 표시를 그린 뒤에는 바깥을 눌러도 선택을 버리지 않는다.
        if let canvas, canvas.hasEdits { return }
        reset()
        session?.beginSelection(on: window as! OverlayWindow)
        dragStart = convert(event.locationInWindow, from: nil)
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
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if resizing != nil {
            resizing = nil
            needsDisplay = true
            return
        }
        defer { dragStart = nil }
        guard dragStart != nil, let selection, selection.width >= 4, selection.height >= 4 else {
            reset()
            return
        }
        beginEditing(selection)
    }

    private func beginEditing(_ rect: CGRect) {
        guard let image = shot.crop(rect) else { reset(); return }
        let canvas = AnnotationCanvas(image: image, pixelScale: shot.scale)
        canvas.frame = rect
        addSubview(canvas)
        self.canvas = canvas

        let toolbar = EditToolbar(canvas: canvas, actions: [
            .init(symbol: "xmark", title: "취소 (Esc)") { [weak self] in self?.session?.cancel() },
            .init(symbol: "checkmark", title: "복사하고 탭에 추가 (↩ 또는 ⌘C)", label: "완료", isPrimary: true) { [weak self] in
                guard let self else { return }
                self.session?.confirm(self)
            },
        ], hint: "안에 드래그해서 표시 · 손잡이·방향키로 영역 조정(⌥ 크기, ⇧ 10px) · ↩ 완료 · Esc 취소")
        addSubview(toolbar)
        self.toolbar = toolbar
        let handles = HandlesView()
        addSubview(handles)
        self.handles = handles
        layoutChrome()
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    /// 영역을 미리 고른 채 편집을 시작한다(화이트보드).
    func preselect(_ rect: CGRect, tool: Tool) {
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
        guard rect.width >= 4, rect.height >= 4, rect != old, let image = shot.crop(rect) else { return }
        selection = rect
        canvas.frame = rect
        canvas.recrop(image, originShift: CGPoint(x: rect.minX - old.minX, y: rect.minY - old.minY))
        layoutChrome()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    /// 방향키: 영역을 옮긴다. ⌥를 누르면 오른쪽·아래 변을 움직여 크기를 바꾼다.
    func nudge(dx: CGFloat, dy: CGFloat, resize: Bool) {
        guard canvas != nil, let selection else { return }
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
        guard let rect = selection else { return }
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
