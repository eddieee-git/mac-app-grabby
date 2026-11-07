import AppKit
import Carbon
import CoreImage

/// 편집 도구. `keyCode`는 도구를 바꾸는 한 글자 단축키다(한글 입력 상태에서도 동작하도록 키 코드로 비교한다).
enum Tool: Int, CaseIterable {
    case select, arrow, rect, pen, text, highlight, mosaic

    var symbol: String {
        switch self {
        case .select: return "rectangle.dashed"
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
        case .select: return L("부분 선택 (V) · ⌘C로 선택한 부분만 복사")
        case .arrow: return L("화살표 (A)")
        case .rect: return L("네모 (R)")
        case .pen: return L("자유그리기 (P)")
        case .text: return L("텍스트 (T)")
        case .highlight: return L("형광펜 (H)")
        case .mosaic: return L("모자이크 (M)")
        }
    }

    /// 설정 화면에 보여 줄 짧은 이름.
    var name: String {
        switch self {
        case .select: return L("부분 선택")
        case .arrow: return L("화살표")
        case .rect: return L("네모")
        case .pen: return L("자유그리기")
        case .text: return L("텍스트")
        case .highlight: return L("형광펜")
        case .mosaic: return L("모자이크")
        }
    }

    /// 설정에 저장할 때 쓰는 이름. 순서를 바꿔도 값이 바뀌지 않게 따로 둔다.
    var key: String {
        switch self {
        case .select: return "select"
        case .arrow: return "arrow"
        case .rect: return "rect"
        case .pen: return "pen"
        case .text: return "text"
        case .highlight: return "highlight"
        case .mosaic: return "mosaic"
        }
    }

    init?(key: String) {
        guard let tool = Tool.allCases.first(where: { $0.key == key }) else { return nil }
        self = tool
    }

    static func forKeyCode(_ code: UInt16) -> Tool? {
        switch Int(code) {
        case kVK_ANSI_V: return .select
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
    case text(String, origin: CGPoint, color: NSColor, size: CGFloat)
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
        case let .text(string, origin, color, size): return .text(string, origin: move(origin), color: color, size: size)
        case let .highlight(r, color): return .highlight(r.offsetBy(dx: dx, dy: dy), color: color)
        case let .mosaic(r): return .mosaic(r.offsetBy(dx: dx, dy: dy))
        }
    }

    var color: NSColor? {
        switch self {
        case let .arrow(_, _, c, _), let .rect(_, c, _), let .pen(_, c, _), let .text(_, _, c, _), let .highlight(_, c): return c
        case .mosaic: return nil
        }
    }

    func withColor(_ c: NSColor) -> Annotation {
        switch self {
        case let .arrow(a, b, _, w): return .arrow(from: a, to: b, color: c, width: w)
        case let .rect(r, _, w): return .rect(r, color: c, width: w)
        case let .pen(p, _, w): return .pen(p, color: c, width: w)
        case let .text(s, o, _, size): return .text(s, origin: o, color: c, size: size)
        case let .highlight(r, _): return .highlight(r, color: c)
        case .mosaic: return self
        }
    }

    /// 굵기 단계(0, 1, 2)를 바꾼다. 텍스트는 글자 크기가 바뀐다.
    func withWidthLevel(_ level: Int) -> Annotation {
        let width = AnnotationCanvas.lineWidths[level]
        switch self {
        case let .arrow(a, b, c, _): return .arrow(from: a, to: b, color: c, width: width)
        case let .rect(r, c, _): return .rect(r, color: c, width: width)
        case let .pen(p, c, _): return .pen(p, color: c, width: width)
        case let .text(s, o, c, _): return .text(s, origin: o, color: c, size: AnnotationCanvas.textSizes[level])
        default: return self
        }
    }

    var widthLevel: Int? {
        switch self {
        case let .arrow(_, _, _, w), let .rect(_, _, w), let .pen(_, _, w): return AnnotationCanvas.lineWidths.firstIndex(of: w)
        case let .text(_, _, _, size): return AnnotationCanvas.textSizes.firstIndex(of: size)
        default: return nil
        }
    }
}

// MARK: 저장 형식 (탭에서 나중에 다시 고칠 수 있게 원본과 함께 저장한다)

extension Annotation: Codable {
    private enum Keys: String, CodingKey { case kind, points, rect, color, width, text, size }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        let color = (try c.decodeIfPresent([CGFloat].self, forKey: .color)).map(Self.color(from:)) ?? .systemRed
        let width = try c.decodeIfPresent(CGFloat.self, forKey: .width) ?? AnnotationCanvas.lineWidths[1]
        switch kind {
        case "arrow":
            let p = try c.decode([CGPoint].self, forKey: .points)
            guard p.count == 2 else { throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "arrow") }
            self = .arrow(from: p[0], to: p[1], color: color, width: width)
        case "rect": self = .rect(try c.decode(CGRect.self, forKey: .rect), color: color, width: width)
        case "pen": self = .pen(try c.decode([CGPoint].self, forKey: .points), color: color, width: width)
        case "text":
            let origin = try c.decode([CGPoint].self, forKey: .points).first ?? .zero
            self = .text(try c.decode(String.self, forKey: .text), origin: origin, color: color,
                         size: try c.decodeIfPresent(CGFloat.self, forKey: .size) ?? AnnotationCanvas.textSizes[1])
        case "highlight": self = .highlight(try c.decode(CGRect.self, forKey: .rect), color: color)
        case "mosaic": self = .mosaic(try c.decode(CGRect.self, forKey: .rect))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .arrow(a, b, color, width):
            try c.encode("arrow", forKey: .kind); try c.encode([a, b], forKey: .points)
            try c.encode(Self.components(color), forKey: .color); try c.encode(width, forKey: .width)
        case let .rect(r, color, width):
            try c.encode("rect", forKey: .kind); try c.encode(r, forKey: .rect)
            try c.encode(Self.components(color), forKey: .color); try c.encode(width, forKey: .width)
        case let .pen(points, color, width):
            try c.encode("pen", forKey: .kind); try c.encode(points, forKey: .points)
            try c.encode(Self.components(color), forKey: .color); try c.encode(width, forKey: .width)
        case let .text(string, origin, color, size):
            try c.encode("text", forKey: .kind); try c.encode([origin], forKey: .points); try c.encode(string, forKey: .text)
            try c.encode(Self.components(color), forKey: .color); try c.encode(size, forKey: .size)
        case let .highlight(r, color):
            try c.encode("highlight", forKey: .kind); try c.encode(r, forKey: .rect); try c.encode(Self.components(color), forKey: .color)
        case let .mosaic(r):
            try c.encode("mosaic", forKey: .kind); try c.encode(r, forKey: .rect)
        }
    }

    /// 팔레트 색은 번호로 다시 찾아 시스템 색(다크 모드에 맞춰 바뀌는 색)을 그대로 쓴다.
    private static func components(_ color: NSColor) -> [CGFloat] {
        if let index = AnnotationCanvas.palette.firstIndex(of: color) { return [-1, CGFloat(index)] }
        let c = color.usingColorSpace(.sRGB) ?? .systemRed
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }

    private static func color(from v: [CGFloat]) -> NSColor {
        if v.count == 2, v[0] == -1, AnnotationCanvas.palette.indices.contains(Int(v[1])) { return AnnotationCanvas.palette[Int(v[1])] }
        guard v.count == 4 else { return .systemRed }
        return NSColor(srgbRed: v[0], green: v[1], blue: v[2], alpha: v[3])
    }
}

/// 이미지를 보여 주고 그 위에 표시를 그리는 뷰. 캡처 직후 화면 위 편집과 탭 창 편집에서 함께 쓴다.
/// 이미 그린 표시는 클릭해서 고르고, 끌어서 옮기고, ⌫로 지우고, 색·굵기를 바꿀 수 있다. 텍스트는 더블클릭해서 고친다.
final class AnnotationCanvas: NSView, NSTextFieldDelegate {
    static let palette: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .black, .white]
    /// 선 굵기 단계: 얇게, 보통, 굵게
    static let lineWidths: [CGFloat] = [2, 4, 8]
    /// 같은 단계의 글자 크기
    static let textSizes: [CGFloat] = [14, 20, 32]

    private(set) var image: CGImage
    /// 이미지 픽셀 수 / 포인트 수
    private(set) var pixelScale: CGFloat
    private(set) var annotations: [Annotation] = [] { didSet { needsDisplay = true; onChange?() } }

    var tool: Tool = .arrow { didSet { commitText(); selectedIndex = nil; onToolChange?() } }
    /// 처음 색과 굵기는 설정의 기본값을 따른다.
    private(set) var color: NSColor = AnnotationCanvas.palette[AppSettings.shared.defaultColorIndex]
    private(set) var widthLevel: Int = AppSettings.shared.defaultWidthIndex
    var lineWidth: CGFloat { Self.lineWidths[widthLevel] }
    var textSize: CGFloat { Self.textSizes[widthLevel] }
    var onChange: (() -> Void)?
    var onToolChange: (() -> Void)?
    /// 확대 배율이 바뀌면 부른다(탭 창이 스크롤 영역 크기를 맞춘다).
    var onZoomChange: (() -> Void)?
    /// 탭 창에서만 켠다. 화면 위 편집은 영역 크기 그대로 보여 준다.
    var allowsZoom = false
    /// nil이면 창에 맞춘다(작은 이미지는 키우지 않는다).
    var zoom: CGFloat? { didSet { needsDisplay = true; onZoomChange?() } }
    /// 불러온 뒤로 표시가 바뀌었는지. 탭 창이 저장할지 정할 때 쓴다.
    private(set) var isDirty = false

    private var draft: Annotation?
    /// 부분 선택 도구로 고른 영역(이미지 좌표). ⌘C로 이 부분만 복사한다.
    private(set) var selectionRect: CGRect? { didSet { needsDisplay = true } }
    /// 클릭해서 고른 표시.
    private(set) var selectedIndex: Int? { didSet { needsDisplay = true } }
    private var dragStart: CGPoint?
    private var moveStart: CGPoint?
    private var movedOriginal: Annotation?
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var pixelatedCache: CGImage?
    private var history: [[Annotation]] = []
    private var future: [[Annotation]] = []

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
    var hasSelectedAnnotation: Bool { selectedIndex != nil }
    var canUndo: Bool { !history.isEmpty || textField != nil }
    var canRedo: Bool { !future.isEmpty }

    /// 새 이미지를 불러온다. `annotations`는 원본 위에 다시 고칠 수 있는 표시다.
    func load(_ image: CGImage, pixelScale: CGFloat, annotations: [Annotation] = []) {
        removeTextField()
        self.image = image
        self.pixelScale = pixelScale
        pixelatedCache = nil
        selectionRect = nil
        selectedIndex = nil
        history = []
        future = []
        self.annotations = annotations
        isDirty = false
        zoom = nil
    }

    func setImage(_ image: CGImage, pixelScale: CGFloat) { load(image, pixelScale: pixelScale) }

    func markSaved() { isDirty = false }

    /// 영역 크기를 조정할 때 쓴다. 그린 표시는 유지하고, 영역의 왼쪽 위가 옮겨진 만큼 반대로 옮긴다.
    func recrop(_ image: CGImage, originShift shift: CGPoint) {
        commitText()
        self.image = image
        pixelatedCache = nil
        selectionRect = selectionRect.map { $0.offsetBy(dx: -shift.x, dy: -shift.y).intersection(CGRect(origin: .zero, size: imageSize)) }
            .flatMap { $0.width >= 3 && $0.height >= 3 ? $0 : nil }
        if shift != .zero {
            annotations = annotations.map { $0.offsetBy(dx: -shift.x, dy: -shift.y) }
            history = history.map { $0.map { $0.offsetBy(dx: -shift.x, dy: -shift.y) } }
            future = future.map { $0.map { $0.offsetBy(dx: -shift.x, dy: -shift.y) } }
        }
        needsDisplay = true
    }

    // MARK: 되돌리기·다시 실행

    /// 표시를 바꾸기 전 상태를 기록하고 바꾼다.
    private func mutate(_ change: (inout [Annotation]) -> Void) {
        history.append(annotations)
        future.removeAll()
        var next = annotations
        change(&next)
        annotations = next
        isDirty = true
    }

    func undo() {
        if textField != nil { removeTextField(); return }
        guard let previous = history.popLast() else { return }
        future.append(annotations)
        selectedIndex = nil
        annotations = previous
        isDirty = true
    }

    func redo() {
        guard let next = future.popLast() else { return }
        history.append(annotations)
        selectedIndex = nil
        annotations = next
        isDirty = true
    }

    // MARK: 색·굵기 (고른 표시가 있으면 그 표시에도 적용)

    func applyColor(_ index: Int) {
        color = Self.palette[index]
        if let i = selectedIndex, annotations.indices.contains(i), annotations[i].color != nil {
            mutate { $0[i] = $0[i].withColor(color) }
        }
        textField?.textColor = color
        onToolChange?()
    }

    func applyWidthLevel(_ level: Int) {
        widthLevel = level
        if let i = selectedIndex, annotations.indices.contains(i), annotations[i].widthLevel != nil {
            mutate { $0[i] = $0[i].withWidthLevel(level) }
        }
        if let field = textField { field.font = .boldSystemFont(ofSize: textSize * viewScale) }
        onToolChange?()
    }

    /// 고른 표시를 지운다. 고른 게 없으면 false.
    @discardableResult
    func deleteSelected() -> Bool {
        guard let i = selectedIndex, annotations.indices.contains(i) else { return false }
        selectedIndex = nil
        mutate { $0.remove(at: i) }
        return true
    }

    /// Esc: 고른 표시나 부분 선택을 푼다. 풀 게 없으면 false.
    func clearSelections() -> Bool {
        if selectedIndex != nil { selectedIndex = nil; return true }
        if selectionRect != nil { selectionRect = nil; return true }
        return false
    }

    // MARK: 좌표 변환

    /// 창에 맞추는 배율(작은 이미지는 키우지 않는다).
    var fitScale: CGFloat {
        let size = imageSize
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(1, bounds.width / size.width, bounds.height / size.height)
    }

    var viewScale: CGFloat { zoom ?? fitScale }

    private var imageOffset: CGPoint {
        let size = imageSize, s = viewScale
        return CGPoint(x: max(0, ((bounds.width - size.width * s) / 2).rounded()), y: max(0, ((bounds.height - size.height * s) / 2).rounded()))
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

    // MARK: 확대·축소 (탭 창)

    func zoomIn() { setZoom(viewScale * 1.25) }
    func zoomOut() { setZoom(viewScale / 1.25) }
    func zoomToFit() { zoom = nil }
    func zoomToActualSize() { setZoom(1) }

    private func setZoom(_ value: CGFloat) {
        guard allowsZoom else { return }
        zoom = min(max(value, 0.1), 8)
    }

    override func magnify(with event: NSEvent) {
        guard allowsZoom else { return super.magnify(with: event) }
        setZoom(viewScale * (1 + event.magnification))
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let o = imageOffset, s = viewScale
        context.translateBy(x: o.x, y: o.y)
        context.scaleBy(x: s, y: s)
        context.interpolationQuality = s >= 2 ? .none : .high
        drawContents(includeDraft: true)
        if let i = selectedIndex, annotations.indices.contains(i) { drawSelectedMark(Self.bounds(of: annotations[i]), viewScale: s) }
        if let selectionRect { drawSelection(selectionRect, viewScale: s) }
        context.restoreGState()
    }

    /// 고른 표시 둘레에 강조 점선을 그린다.
    private func drawSelectedMark(_ rect: CGRect, viewScale s: CGFloat) {
        let box = NSBezierPath(rect: rect.insetBy(dx: -4 / s, dy: -4 / s))
        box.lineWidth = 1.5 / s
        box.setLineDash([5 / s, 3 / s], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        box.stroke()
    }

    /// 선택 영역 밖을 살짝 어둡게 하고 점선 테두리를 그린다.
    private func drawSelection(_ rect: CGRect, viewScale s: CGFloat) {
        let dim = NSBezierPath(rect: CGRect(origin: .zero, size: imageSize))
        dim.append(NSBezierPath(rect: rect))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.3).setFill()
        dim.fill()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1 / s
        NSColor.white.setStroke()
        border.stroke()
        border.setLineDash([4 / s, 4 / s], count: 2, phase: 0)
        NSColor.black.setStroke()
        border.stroke()
    }

    func clearSelection() { selectionRect = nil }

    /// 표시를 합친 이미지에서 선택한 부분만 잘라 낸다. 선택이 없으면 nil.
    func selectedImage() -> CGImage? {
        guard let rect = selectionRect else { return nil }
        return render().cropping(to: pixelRect(rect))
    }

    /// 원본(표시 없이)에서 선택한 부분만 잘라 낸다.
    func selectedOriginal() -> CGImage? {
        guard let rect = selectionRect else { return nil }
        return image.cropping(to: pixelRect(rect))
    }

    private func pixelRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * pixelScale, y: rect.minY * pixelScale, width: rect.width * pixelScale, height: rect.height * pixelScale).integral
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: tool == .text ? .iBeam : .crosshair)
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
        case let .text(string, origin, color, size):
            (string as NSString).draw(at: origin, withAttributes: Self.textAttributes(color: color, size: size))
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

    // MARK: 표시 고르기

    /// 표시가 차지하는 영역(이미지 좌표).
    static func bounds(of annotation: Annotation) -> CGRect {
        switch annotation {
        case let .arrow(a, b, _, w):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -w * 2, dy: -w * 2)
        case let .rect(r, _, w): return r.insetBy(dx: -w / 2, dy: -w / 2)
        case let .pen(points, _, w):
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -w / 2, dy: -w / 2)
        case let .text(string, origin, color, size):
            return CGRect(origin: origin, size: (string as NSString).size(withAttributes: textAttributes(color: color, size: size)))
        case let .highlight(r, _), let .mosaic(r): return r
        }
    }

    private static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// 클릭한 자리의 맨 위 표시. 그리기 도구일 때는 면을 덮는 형광펜·모자이크는 고르지 않는다(그 위에 그릴 수 있게).
    private func annotationIndex(at p: CGPoint, includeAreas: Bool) -> Int? {
        let t = 6 / viewScale
        for (i, annotation) in annotations.enumerated().reversed() {
            switch annotation {
            case let .arrow(a, b, _, w):
                if Self.distance(p, toSegment: a, b) <= w / 2 + t { return i }
            case let .rect(r, _, w):
                let outer = r.insetBy(dx: -w / 2 - t, dy: -w / 2 - t)
                let inner = r.insetBy(dx: w / 2 + t, dy: w / 2 + t)
                if outer.contains(p) && (inner.isEmpty || !inner.contains(p)) { return i }
            case let .pen(points, _, w):
                for (a, b) in zip(points, points.dropFirst()) where Self.distance(p, toSegment: a, b) <= w / 2 + t { return i }
            case .text:
                if Self.bounds(of: annotation).insetBy(dx: -t, dy: -t).contains(p) { return i }
            case let .highlight(r, _), let .mosaic(r):
                if includeAreas && r.contains(p) { return i }
            }
        }
        return nil
    }

    // MARK: 마우스

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if textField != nil {
            commitText()
            return
        }
        let point = toImage(location)

        // 이미 그린 표시를 누르면 고르고, 끌면 옮긴다. 텍스트는 더블클릭하면 고친다.
        if let i = annotationIndex(at: point, includeAreas: tool == .select) {
            if event.clickCount == 2, case let .text(string, origin, textColor, size) = annotations[i] {
                selectedIndex = nil
                mutate { $0.remove(at: i) }
                beginText(at: origin, string: string, color: textColor, size: size)
                return
            }
            selectedIndex = i
            moveStart = point
            movedOriginal = annotations[i]
            if let c = annotations[i].color { color = c }
            if let level = annotations[i].widthLevel { widthLevel = level }
            onToolChange?()
            return
        }
        selectedIndex = nil

        if tool == .select {
            selectionRect = nil
            dragStart = point
            return
        }
        if tool == .text {
            beginText(at: point, string: "", color: color, size: textSize)
            return
        }
        dragStart = point
        if tool == .pen { draft = .pen([point], color: color, width: lineWidth) }
    }

    override func mouseDragged(with event: NSEvent) {
        var point = toImage(convert(event.locationInWindow, from: nil))
        if let start = moveStart, let original = movedOriginal, let i = selectedIndex, annotations.indices.contains(i) {
            // 처음 움직일 때 한 번만 되돌리기 기록을 남긴다.
            if !isMovingRecorded {
                history.append(annotations)
                future.removeAll()
                isMovingRecorded = true
                isDirty = true
            }
            var next = annotations
            next[i] = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            annotations = next
            return
        }
        guard let start = dragStart else { return }
        if tool == .select {
            if event.modifierFlags.contains(.shift) { point = Self.constrain(point, from: start, square: true) }
            selectionRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                                   width: abs(point.x - start.x), height: abs(point.y - start.y))
            return
        }
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
        case .text, .pen, .select: break
        }
        needsDisplay = true
    }

    private var isMovingRecorded = false

    override func mouseUp(with event: NSEvent) {
        if moveStart != nil {
            moveStart = nil
            movedOriginal = nil
            isMovingRecorded = false
            return
        }
        if tool == .select {
            if let r = selectionRect, r.width < 3 || r.height < 3 { selectionRect = nil }
            dragStart = nil
            return
        }
        defer { draft = nil; dragStart = nil; needsDisplay = true }
        guard let draft, isMeaningful(draft) else { return }
        mutate { $0.append(draft) }
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

    private func beginText(at point: CGPoint, string: String, color textColor: NSColor, size: CGFloat) {
        let s = viewScale
        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.6)
        field.focusRingType = .none
        field.font = .boldSystemFont(ofSize: size * s)
        field.textColor = textColor
        field.delegate = self
        field.cell?.isScrollable = true
        let origin = toView(point)
        // NSTextField 안쪽 여백만큼 당겨서 입력하던 위치와 그려지는 위치를 맞춘다.
        let width = max(160, min(400, bounds.width - origin.x), (string as NSString).size(withAttributes: [.font: field.font!]).width + 30)
        field.frame = CGRect(x: origin.x - 2, y: origin.y, width: width, height: (size + 8) * s)
        addSubview(field)
        textField = field
        textOrigin = point
        if let level = Self.textSizes.firstIndex(of: size) { widthLevel = level }
        color = textColor
        onToolChange?()
        window?.makeFirstResponder(field)
    }

    /// 입력 중인 텍스트가 있으면 표시로 확정한다.
    func commitText() {
        guard let field = textField else { return }
        let string = field.stringValue
        let textColor = field.textColor ?? color
        removeTextField()
        guard !string.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let size = textSize
        mutate { $0.append(.text(string, origin: textOrigin, color: textColor, size: size)) }
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
