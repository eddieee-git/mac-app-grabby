import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 보관함의 캡처 하나. 이미지는 `<id>.png`로 따로 저장한다.
struct CaptureItem: Codable, Equatable {
    let id: UUID
    let date: Date
    var width: Int
    var height: Int
    /// 이미지 픽셀 수 / 포인트 수
    var scale: CGFloat
}

/// 캡처를 ~/Library/Application Support/Grabby/Captures에 저장한다. 최근 `limit`개만 남긴다.
final class CaptureStore {
    static let shared = CaptureStore()
    static let didChange = Notification.Name("CaptureStoreDidChange")
    static let limit = 100

    private(set) var items: [CaptureItem] = []
    private let directory: URL
    private var thumbnails: [UUID: NSImage] = [:]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Grabby/Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([CaptureItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
        }
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    func url(for item: CaptureItem) -> URL { directory.appendingPathComponent("\(item.id.uuidString).png") }

    @discardableResult
    func add(_ image: CGImage, scale: CGFloat) -> CaptureItem {
        let item = CaptureItem(id: UUID(), date: Date(), width: image.width, height: image.height, scale: scale)
        write(image, to: url(for: item))
        items.insert(item, at: 0)
        while items.count > Self.limit { delete(items.removeLast()) }
        save()
        return item
    }

    func replace(_ item: CaptureItem, with image: CGImage) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        write(image, to: url(for: item))
        items[index].width = image.width
        items[index].height = image.height
        thumbnails[item.id] = nil
        save()
    }

    func remove(_ item: CaptureItem) {
        items.removeAll { $0.id == item.id }
        delete(item)
        save()
    }

    func image(for item: CaptureItem) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url(for: item) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func thumbnail(for item: CaptureItem) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let source = CGImageSourceCreateWithURL(url(for: item) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 400,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails[item.id] = image
        return image
    }

    private func delete(_ item: CaptureItem) {
        try? FileManager.default.removeItem(at: url(for: item))
        thumbnails[item.id] = nil
    }

    private func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

enum Clipboard {
    /// PNG로 복사한다. 해상도 정보(DPI)를 넣어 문서 앱에서도 화면에서 보던 크기로 붙여 넣어지게 한다.
    static func copy(_ image: CGImage, scale: CGFloat) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) { pasteboard.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }
}
