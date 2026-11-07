import AppKit
import Carbon
import CoreImage

/// 편집 도구. `keyCode`는 도구를 바꾸는 한 글자 단축키다(한글 입력 상태에서도 동작하도록 키 코드로 비교한다).
enum Tool: Int, CaseIterable {
    case arrow, rect, pen, text, highlight, mosaic

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .pen: return "scribble"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .mosaic: return "square.grid.3x3.fill"
        }
    }

    var title: String {
        switch self {
        case .arrow: return "화살표 (A)"
        case .rect: return "네모 (R)"
        case .pen: return "자유그리기 (P)"
        case .text: return "텍스트 (T)"
        case .highlight: return "형광펜 (H)"
        case .mosaic: return "모자이크 (M)"
        }
    }

    static func forKeyCode(_ code: UInt16) -> Tool? {
        switch Int(code) {
        case kVK_ANSI_A: return .arrow
        case kVK_ANSI_R: return .rect
        case kVK_ANSI_P: return .pen
        case kVK_ANSI_T: return .text
        case kVK_ANSI_H: return .highlight
        case kVK_ANSI_M: return .mosaic
        default: return nil
        }
    }
}

/// 이미지 위에 그린 표시 하나. 좌표는 이미지의 왼쪽 위 기준 포인트 단위다.
enum Annotation {
    case arrow(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat)
    case rect(CGRect, color: NSColor, width: CGFloat)
    case pen([CGPoint], color: NSColor, width: CGFloat)
    case text(String, origin: CGPoint, color: NSColor)
    case highlight(CGRect, color: NSColor)
    case mosaic(CGRect)
}

extension Annotation {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> Annotation {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
        switch self {
        case let .arrow(from, to, color, width): return .arrow(from: move(from), to: move(to), color: color, width: width)
        case let .rect(r, color, width): return .rect(r.offsetBy(dx: dx, dy: dy), color: color, width: width)
        case let .pen(points, color, width): return .pen(points.map(move), color: color, width: width)
        case let .text(string, origin, color): return .text(string, origin: move(origin), color: color)
        case let .highlight(r, color): return .highlight(r.offsetBy(dx: dx, dy: dy), color: color)
        case let .mosaic(r): return .mosaic(r.offsetBy(dx: dx, dy: dy))
        }
    }
}

/// 이미지를 보여 주고 그 위에 표시를 그리는 뷰. 캡처 직후 화면 위 편집과 보관함 편집에서 함께 쓴다.
final class AnnotationCanvas: NSView, NSTextFieldDelegate {
    static let palette: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .black, .white]
    static let fontSize: CGFloat = 20
    /// 선 굵기 단계: 얇게, 보통, 굵게
    static let lineWidths: [CGFloat] = [2, 4, 8]

    private(set) var image: CGImage
    /// 이미지 픽셀 수 / 포인트 수
    private(set) var pixelScale: CGFloat
    private(set) var annotations: [Annotation] = [] { didSet { onChange?() } }

    var tool: Tool = .arrow { didSet { commitText(); onToolChange?() } }
    var color: NSColor = AnnotationCanvas.palette[0] { didSet { onToolChange?() } }
    var lineWidth: CGFloat = AnnotationCanvas.lineWidths[1] { didSet { onToolChange?() } }
    var onChange: (() -> Void)?
    var onToolChange: (() -> Void)?

    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var pixelatedCache: CGImage?

    init(image: CGImage, pixelScale: CGFloat) {
        self.image = image
        self.pixelScale = pixelScale
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var imageSize: CGSize { CGSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale) }
    var hasEdits: Bool { !annotations.isEmpty || !(textField?.stringValue.isEmpty ?? true) }
    var isEditingText: Bool { textField != nil }

    func setImage(_ image: CGImage, pixelScale: CGFloat) {
        removeTextField()
        self.image = image
        self.pixelScale = pixelScale
        pixelatedCache = nil
        annotations = []
        needsDisplay = true
    }

    /// 영역 크기를 조정할 때 쓴다. 그린 표시는 유지하고, 영역의 왼쪽 위가 옮겨진 만큼 반대로 옮긴다.
    func recrop(_ image: CGImage, originShift shift: CGPoint) {
        commitText()
        self.image = image
        pixelatedCache = nil
        if shift != .zero {
            annotations = annotations.map { $0.offsetBy(dx: -shift.x, dy: -shift.y) }
        }
        needsDisplay = true
    }

    func undo() {
        if textField != nil { removeTextField(); return }
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    // MARK: 좌표 변환 (뷰보다 큰 이미지만 줄여서 가운데에 놓는다)

    private var viewScale: CGFloat {
        let size = imageSize
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(1, bounds.width / size.width, bounds.height / size.height)
    }

    private var imageOffset: CGPoint {
        let size = imageSize, s = viewScale
        return CGPoint(x: ((bounds.width - size.width * s) / 2).rounded(), y: ((bounds.height - size.height * s) / 2).rounded())
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        let o = imageOffset, s = viewScale
        let size = imageSize
        return CGPoint(x: min(max((p.x - o.x) / s, 0), size.width), y: min(max((p.y - o.y) / s, 0), size.height))
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        let o = imageOffset, s = viewScale
        return CGPoint(x: p.x * s + o.x, y: p.y * s + o.y)
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let o = imageOffset, s = viewScale
        context.translateBy(x: o.x, y: o.y)
        context.scaleBy(x: s, y: s)
        context.interpolationQuality = .high
        drawContents(includeDraft: true)
        context.restoreGState()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair)
    }

    /// 현재 그래픽 컨텍스트가 뒤집힌(왼쪽 위 원점) 이미지 포인트 좌표계라고 보고 그린다.
    private func drawContents(includeDraft: Bool) {
        let full = CGRect(origin: .zero, size: imageSize)
        NSImage(cgImage: image, size: full.size)
            .draw(in: full, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        for annotation in annotations { draw(annotation) }
        if includeDraft, let draft { draw(draft) }
    }

    private func draw(_ annotation: Annotation) {
        switch annotation {
        case let .arrow(from, to, color, width):
            Self.drawArrow(from: from, to: to, color: color, width: width)
        case let .rect(rect, color, width):
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            path.lineWidth = width
            color.setStroke()
            path.stroke()
        case let .pen(points, color, width):
            Self.drawPen(points, color: color, width: width)
        case let .text(string, origin, color):
            (string as NSString).draw(at: origin, withAttributes: Self.textAttributes(color: color, size: Self.fontSize))
        case let .highlight(rect, color):
            color.withAlphaComponent(0.35).setFill()
            rect.fill(using: .sourceOver)
        case let .mosaic(rect):
            guard let pixelated else { return }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            let full = CGRect(origin: .zero, size: imageSize)
            NSImage(cgImage: pixelated, size: full.size)
                .draw(in: full, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func textAttributes(color: NSColor, size: CGFloat) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = (color == .white ? NSColor.black : NSColor.white).withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        return [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: color, .shadow: shadow]
    }

    /// 점 사이를 중간점 곡선으로 이어 손떨림을 부드럽게 한다.
    private static func drawPen(_ points: [CGPoint], color: NSColor, width: CGFloat) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        if points.count < 3 {
            for p in points.dropFirst() { path.line(to: p) }
        } else {
            for i in 1..<points.count - 1 {
                let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
                path.curve(to: mid, controlPoint1: points[i], controlPoint2: points[i])
            }
            path.line(to: points[points.count - 1])
        }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func drawArrow(from a: CGPoint, to b: CGPoint, color: NSColor, width: CGFloat) {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 1 else { return }
        let head = min(max(14, width * 4.5), length * 0.6)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let spread: CGFloat = 0.45
        let base = CGPoint(x: b.x - cos(angle) * head * 0.8, y: b.y - sin(angle) * head * 0.8)

        color.set()
        let line = NSBezierPath()
        line.move(to: a)
        line.line(to: base)
        line.lineWidth = width
        line.lineCapStyle = .round
        line.stroke()

        let tip = NSBezierPath()
        tip.move(to: b)
        tip.line(to: CGPoint(x: b.x - cos(angle - spread) * head, y: b.y - sin(angle - spread) * head))
        tip.line(to: CGPoint(x: b.x - cos(angle + spread) * head, y: b.y - sin(angle + spread) * head))
        tip.close()
        tip.lineJoinStyle = .round
        tip.lineWidth = 2
        tip.fill()
        tip.stroke()
    }

    /// 모자이크용으로 이미지 전체를 한 번만 픽셀화해 둔다.
    private var pixelated: CGImage? {
        if let pixelatedCache { return pixelatedCache }
        let source = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(8, 10 * pixelScale), forKey: kCIInputScaleKey)
        guard let output = filter.outputImage?.cropped(to: source.extent) else { return nil }
        pixelatedCache = CIContext().createCGImage(output, from: source.extent)
        return pixelatedCache
    }

    /// 표시를 그려 넣은 원본 해상도 이미지.
    func render() -> CGImage {
        commitText()
        guard !annotations.isEmpty else { return image }
        let width = image.width, height = image.height
        var space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        if space.model != .rgb { space = CGColorSpace(name: CGColorSpace.sRGB)! }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: pixelScale, y: pixelScale)
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawContents(includeDraft: false)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage() ?? image
    }

    // MARK: 마우스

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if textField != nil {
            commitText()
            return
        }
        let point = toImage(location)
        if tool == .text {
            beginText(at: point)
            return
        }
        dragStart = point
        if tool == .pen { draft = .pen([point], color: color, width: lineWidth) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        var point = toImage(convert(event.locationInWindow, from: nil))
        if tool == .pen {
            if case let .pen(points, penColor, width) = draft, let last = points.last, hypot(point.x - last.x, point.y - last.y) >= 1 {
                draft = .pen(points + [point], color: penColor, width: width)
                needsDisplay = true
            }
            return
        }
        if event.modifierFlags.contains(.shift) { point = Self.constrain(point, from: start, square: tool != .arrow) }
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        switch tool {
        case .arrow: draft = .arrow(from: start, to: point, color: color, width: lineWidth)
        case .rect: draft = .rect(rect, color: color, width: lineWidth)
        case .highlight: draft = .highlight(rect, color: color)
        case .mosaic: draft = .mosaic(rect)
        case .text, .pen: break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { draft = nil; dragStart = nil; needsDisplay = true }
        guard let draft, isMeaningful(draft) else { return }
        annotations.append(draft)
    }

    /// Shift를 누르면 화살표는 45도 단위, 네모는 정사각형으로 맞춘다.
    private static func constrain(_ p: CGPoint, from start: CGPoint, square: Bool) -> CGPoint {
        let dx = p.x - start.x, dy = p.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }

    private func isMeaningful(_ annotation: Annotation) -> Bool {
        switch annotation {
        case let .arrow(from, to, _, _): return hypot(to.x - from.x, to.y - from.y) > 4
        case let .rect(r, _, _), let .highlight(r, _), let .mosaic(r): return r.width > 3 && r.height > 3
        case let .pen(points, _, _): return points.count > 1
        case .text: return true
        }
    }

    // MARK: 텍스트 입력

    private func beginText(at point: CGPoint) {
        let s = viewScale
        let field = NSTextField(string: "")
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.6)
        field.focusRingType = .none
        field.font = .boldSystemFont(ofSize: Self.fontSize * s)
        field.textColor = color
        field.delegate = self
        field.cell?.isScrollable = true
        let origin = toView(point)
        // NSTextField 안쪽 여백만큼 당겨서 입력하던 위치와 그려지는 위치를 맞춘다.
        field.frame = CGRect(x: origin.x - 2, y: origin.y, width: max(160, min(400, bounds.width - origin.x)) , height: (Self.fontSize + 6) * s)
        addSubview(field)
        textField = field
        textOrigin = point
        window?.makeFirstResponder(field)
    }

    /// 입력 중인 텍스트가 있으면 표시로 확정한다.
    func commitText() {
        guard let field = textField else { return }
        let string = field.stringValue
        removeTextField()
        guard !string.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        annotations.append(.text(string, origin: textOrigin, color: color))
        needsDisplay = true
    }

    private func removeTextField() {
        guard let field = textField else { return }
        textField = nil
        field.delegate = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(window?.contentView)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commitText()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            removeTextField()
            return true
        default:
            return false
        }
    }
}
