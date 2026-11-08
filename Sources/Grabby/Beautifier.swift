import AppKit

/// 캡처를 보기 좋게 꾸민다: 여백, 배경, 둥근 모서리, 그림자.
enum Beautifier {
    enum Background: String, CaseIterable {
        case ocean, sunset, forest, gray, white

        var title: String {
            switch self {
            case .ocean: return L("바다")
            case .sunset: return L("노을")
            case .forest: return L("숲")
            case .gray: return L("회색")
            case .white: return L("흰색")
            }
        }

        /// 왼쪽 아래 → 오른쪽 위로 이어지는 두 색.
        var colors: (CGColor, CGColor) {
            switch self {
            case .ocean: return (CGColor(srgbRed: 0.26, green: 0.45, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.45, green: 0.85, blue: 0.95, alpha: 1))
            case .sunset: return (CGColor(srgbRed: 0.98, green: 0.45, blue: 0.40, alpha: 1), CGColor(srgbRed: 0.99, green: 0.78, blue: 0.40, alpha: 1))
            case .forest: return (CGColor(srgbRed: 0.18, green: 0.60, blue: 0.45, alpha: 1), CGColor(srgbRed: 0.65, green: 0.88, blue: 0.55, alpha: 1))
            case .gray: return (CGColor(srgbRed: 0.42, green: 0.45, blue: 0.50, alpha: 1), CGColor(srgbRed: 0.72, green: 0.75, blue: 0.80, alpha: 1))
            case .white: return (CGColor(gray: 0.96, alpha: 1), CGColor(gray: 1, alpha: 1))
            }
        }
    }

    /// 여백 단계(포인트)
    static let paddings: [CGFloat] = [24, 48, 80]

    static func apply(_ image: CGImage, scale: CGFloat) -> CGImage {
        let settings = AppSettings.shared
        let pad = paddings[min(max(settings.beautifyPadding, 0), 2)] * scale
        let radius = 10 * scale
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let size = CGSize(width: w + pad * 2, height: h + pad * 2)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let (start, end) = settings.beautifyBackground.colors
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [start, end] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        let frame = CGRect(x: pad, y: pad, width: w, height: h)
        let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // 그림자는 모양을 한 번 채워서 만들고, 그 위에 둥글게 자른 이미지를 그린다.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 30 * scale, color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(path)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(image, in: frame)
        context.restoreGState()
        return context.makeImage() ?? image
    }
}
