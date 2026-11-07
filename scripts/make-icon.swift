// Grabby 앱 아이콘을 그려 Resources/AppIcon.icns를 만든다.
// 실행: swift scripts/make-icon.swift
import AppKit

func draw(in size: CGFloat) {
    let scale = size / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)

    // 배경: macOS 아이콘 격자에 맞춘 둥근 사각형
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.45, blue: 0.30, alpha: 1),
               ending: NSColor(srgbRed: 0.93, green: 0.25, blue: 0.48, alpha: 1))!.draw(in: tile, angle: 60)

    // 캡처한 조각: 살짝 기울어진 흰 카드
    context.saveGState()
    context.translateBy(x: 512, y: 500)
    context.rotate(by: -5 * .pi / 180)
    context.setShadow(offset: CGSize(width: 0, height: -30 * scale), blur: 60 * scale,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
    let card = NSBezierPath(roundedRect: NSRect(x: -230, y: -170, width: 460, height: 340), xRadius: 28, yRadius: 28)
    NSColor.white.setFill()
    card.fill()
    context.restoreGState()

    context.saveGState()
    context.translateBy(x: 512, y: 500)
    context.rotate(by: -5 * .pi / 180)
    // 카드 속 화살표 표시
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: -120, y: -80))
    arrow.line(to: NSPoint(x: 70, y: 60))
    arrow.lineWidth = 34
    arrow.lineCapStyle = .round
    NSColor(srgbRed: 0.93, green: 0.25, blue: 0.40, alpha: 1).set()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 130, y: 105))
    head.line(to: NSPoint(x: 10, y: 95))
    head.line(to: NSPoint(x: 100, y: -5))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 20
    head.fill()
    head.stroke()
    context.restoreGState()

    // 영역 선택 모서리 표시
    NSColor.white.setStroke()
    let corners = NSBezierPath()
    let inset: CGFloat = 190, length: CGFloat = 110
    for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (1024 - inset, inset, -1.0, 1.0),
                           (inset, 1024 - inset, 1.0, -1.0), (1024 - inset, 1024 - inset, -1.0, -1.0)] {
        corners.move(to: NSPoint(x: x, y: y + dy * length))
        corners.line(to: NSPoint(x: x, y: y))
        corners.line(to: NSPoint(x: x + dx * length, y: y))
    }
    corners.lineWidth = 30
    corners.lineCapStyle = .round
    corners.lineJoinStyle = .round
    corners.stroke()
}

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(in: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GrabbyIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
