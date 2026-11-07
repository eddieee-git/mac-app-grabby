import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 보관함의 캡처 하나.
/// - `<id>.png`: 표시를 합친 이미지(복사·끌어다 놓기·썸네일에 쓴다)
/// - `<id>.orig.png`, `<id>.json`: 표시가 있을 때만. 원본과 표시를 따로 두어 나중에 다시 고칠 수 있게 한다.
struct CaptureItem: Codable, Equatable {
    let id: UUID
    let date: Date
    var width: Int
    var height: Int
    /// 이미지 픽셀 수 / 포인트 수
    var scale: CGFloat
    /// 고정한 캡처는 보관 개수를 넘어도 자동으로 지우지 않는다.
    var isKept = false

    private enum CodingKeys: String, CodingKey { case id, date, width, height, scale, isKept }

    init(id: UUID, date: Date, width: Int, height: Int, scale: CGFloat) {
        self.id = id
        self.date = date
        self.width = width
        self.height = height
        self.scale = scale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        scale = try c.decode(CGFloat.self, forKey: .scale)
        isKept = try c.decodeIfPresent(Bool.self, forKey: .isKept) ?? false
    }
}

/// 캡처를 ~/Library/Application Support/Grabby/Captures에 저장한다. 설정한 개수만 남기되 고정한 캡처는 지우지 않는다.
final class CaptureStore {
    static let shared = CaptureStore()
    static let didChange = Notification.Name("CaptureStoreDidChange")

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
    private func originalURL(for item: CaptureItem) -> URL { directory.appendingPathComponent("\(item.id.uuidString).orig.png") }
    private func annotationsURL(for item: CaptureItem) -> URL { directory.appendingPathComponent("\(item.id.uuidString).json") }

    /// 새 캡처를 맨 앞에 넣는다. 보관 개수를 넘겨 지운 캡처 수를 함께 돌려준다.
    @discardableResult
    func add(_ image: CGImage, scale: CGFloat, original: CGImage? = nil, annotations: [Annotation] = []) -> (item: CaptureItem, pruned: Int) {
        let item = CaptureItem(id: UUID(), date: Date(), width: image.width, height: image.height, scale: scale)
        write(image, to: url(for: item))
        writeEditable(item, original: original, annotations: annotations)
        items.insert(item, at: 0)
        let pruned = prune()
        save()
        return (item, pruned)
    }

    /// 보관 개수를 넘는 오래된 캡처를 지운다(고정한 캡처는 빼고 센다). 0이면 무제한.
    @discardableResult
    func prune() -> Int {
        let limit = AppSettings.shared.keepCount
        guard limit > 0 else { return 0 }
        var unkept = 0, removed = 0
        items = items.filter { item in
            if item.isKept { return true }
            unkept += 1
            if unkept <= limit { return true }
            delete(item)
            removed += 1
            return false
        }
        return removed
    }

    /// 표시를 고친 결과를 저장한다. `original`과 `annotations`가 있으면 다시 고칠 수 있게 함께 둔다.
    func replace(_ item: CaptureItem, with image: CGImage, original: CGImage? = nil, annotations: [Annotation] = []) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        write(image, to: url(for: item))
        writeEditable(item, original: original, annotations: annotations)
        items[index].width = image.width
        items[index].height = image.height
        thumbnails[item.id] = nil
        save()
    }

    func setKept(_ item: CaptureItem, _ kept: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isKept = kept
        if !kept { prune() }
        save()
    }

    func remove(_ item: CaptureItem) {
        items.removeAll { $0.id == item.id }
        delete(item)
        save()
    }

    func image(for item: CaptureItem) -> CGImage? { load(url(for: item)) }

    /// 다시 고칠 수 있는 형태: 원본과 표시. 표시 없이 저장된 캡처는 그 이미지 그대로.
    func editable(for item: CaptureItem) -> (image: CGImage, annotations: [Annotation])? {
        if let original = load(originalURL(for: item)),
           let data = try? Data(contentsOf: annotationsURL(for: item)),
           let annotations = try? JSONDecoder().decode([Annotation].self, from: data) {
            return (original, annotations)
        }
        return image(for: item).map { ($0, []) }
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

    private func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func writeEditable(_ item: CaptureItem, original: CGImage?, annotations: [Annotation]) {
        if let original, !annotations.isEmpty, let data = try? JSONEncoder().encode(annotations) {
            write(original, to: originalURL(for: item))
            try? data.write(to: annotationsURL(for: item), options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: originalURL(for: item))
            try? FileManager.default.removeItem(at: annotationsURL(for: item))
        }
    }

    private func delete(_ item: CaptureItem) {
        for url in [url(for: item), originalURL(for: item), annotationsURL(for: item)] { try? FileManager.default.removeItem(at: url) }
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

    static func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
