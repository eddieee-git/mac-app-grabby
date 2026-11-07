import AppKit
import Carbon

/// 영역 캡처를 마친 결과. `rect`는 화면 왼쪽 위 기준 포인트 좌표다.
struct CaptureResult {
    let image: CGImage
    let pixelScale: CGFloat
    let rect: CGRect
    let displayID: CGDirectDisplayID
}

/// 멈춘 화면들을 덮어 영역을 고르고, 고른 자리에서 바로 편집하게 한다.
final class CaptureSession {
    private var windows: [OverlayWindow] = []
    private let completion: (CaptureResult?) -> Void
    private var finished = false

    init(shots: [ScreenShot], completion: @escaping (CaptureResult?) -> Void) {
        self.completion = completion
        windows = shots.map { OverlayWindow(shot: $0, session: self) }
        let mouse = NSEvent.mouseLocation
        for window in windows { window.orderFrontRegardless() }
        // 마우스가 있는 화면이 키 입력을 받게 한다.
        let active = windows.first { $0.frame.contains(mouse) } ?? windows.first
        active?.makeKeyAndOrderFront(nil)
    }

    /// 한 화면에서 새로 영역을 고르기 시작하면 다른 화면의 선택은 지운다.
    fileprivate func beginSelection(on window: OverlayWindow) {
        for other in windows where other !== window { other.overlay.reset() }
        if !window.isKeyWindow { window.makeKey() }
    }

    fileprivate func confirm(_ overlay: OverlayView) {
        guard let canvas = overlay.canvas, let rect = overlay.selection else { return }
        finish(CaptureResult(image: canvas.render(), pixelScale: canvas.pixelScale, rect: rect, displayID: overlay.shot.displayID))
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
    private var dragStart: CGPoint?

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
        canvas = nil
        toolbar = nil
        selection = nil
        dragStart = nil
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
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
        if canvas == nil { drawSizeLabel(for: selection) }
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
        // 표시를 그린 뒤에는 바깥을 눌러도 선택을 버리지 않는다.
        if let canvas, canvas.hasEdits { return }
        reset()
        session?.beginSelection(on: window as! OverlayWindow)
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        let x = min(max(p.x, 0), bounds.width), y = min(max(p.y, 0), bounds.height)
        selection = CGRect(x: min(start.x, x), y: min(start.y, y), width: abs(x - start.x), height: abs(y - start.y)).integral
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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
            .init(symbol: "checkmark", title: "복사하고 보관 (↩ 또는 ⌘C)") { [weak self] in
                guard let self else { return }
                self.session?.confirm(self)
            },
        ])
        // 선택 영역 아래 오른쪽에 붙이고, 자리가 없으면 위, 그래도 없으면 안쪽 아래에 둔다.
        let size = toolbar.frame.size, gap: CGFloat = 8
        var origin = CGPoint(x: rect.maxX - size.width, y: rect.maxY + gap)
        if origin.y + size.height > bounds.height {
            origin.y = rect.minY - gap - size.height
            if origin.y < 0 { origin.y = rect.maxY - gap - size.height }
        }
        origin.x = min(max(origin.x, gap), bounds.width - size.width - gap)
        toolbar.frame = CGRect(origin: origin, size: size)
        addSubview(toolbar)
        self.toolbar = toolbar
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}
