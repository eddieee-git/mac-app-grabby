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
    /// 사용자가 붙인 메모. 탭 이름 대신 보이고 검색된다.
    var note: String?
    /// 이미지에서 인식한 글자. nil이면 아직 인식하지 않았다. 검색에 쓴다.
    var text: String?

    private enum CodingKeys: String, CodingKey { case id, date, width, height, scale, isKept, note, text }

    /// 메모와 인식한 글자에서 찾는다.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [note, text].contains { $0?.localizedCaseInsensitiveContains(q) == true }
    }

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
        note = try c.decodeIfPresent(String.self, forKey: .note)
        text = try c.decodeIfPresent(String.self, forKey: .text)
    }
}

/// 캡처를 ~/Library/Application Support/Grabby/Captures에 저장한다. 설정한 개수만 남기되 고정한 캡처는 지우지 않는다.
final class CaptureStore {
    static let shared = CaptureStore()
    static let didChange = Notification.Name("CaptureStoreDidChange")

    private(set) var items: [CaptureItem] = []
    private let directory: URL
    private var thumbnails: [UUID: NSImage] = [:]

    private convenience init() {
        // 예시 화면을 만들 때는 `-captureFolder <경로>` 인자로 다른 보관함을 쓴다.
        #if DEBUG
        let custom = UserDefaults.standard.string(forKey: "captureFolder")
        #else
        let custom: String? = nil
        #endif
        if let custom {
            self.init(directory: URL(fileURLWithPath: custom, isDirectory: true))
            return
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(directory: support.appendingPathComponent("Grabby/Captures", isDirectory: true))
    }

    /// 테스트에서는 임시 폴더를 넘겨 실제 보관함을 건드리지 않는다.
    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([CaptureItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
        }
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    func url(for item: CaptureItem) -> URL { directory.appendingPathComponent("\(item.id.uuidString).png") }
    private func originalURL(for item: CaptureItem) -> URL { directory.appendingPathComponent("\(item.id.uuidString).orig.png") }
    private func annotationsURL(for item: CaptureItem) -> URL { directory.appendingPathComponent("\(item.id.uuidString).json") }

    /// 파일 쓰기와 지우기는 이 줄에서 차례대로 한다. 캡처를 마치는 순간 화면이 멈칫하지 않게 하려는 것이다.
    private let io = DispatchQueue(label: "com.eddieee.Grabby.store", qos: .utility)
    /// 아직 디스크에 다 쓰지 않은 이미지. 쓰는 동안 읽으면 여기서 준다.
    private var pending: [URL: CGImage] = [:]

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
    func prune() -> Int { prune(limit: AppSettings.shared.keepCount) }

    @discardableResult
    func prune(limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        var unkept = 0, removed = 0
        items = items.filter { item in
            if item.isKept { return true }
            unkept += 1
            if unkept <= limit { return true }
            delete(item, reason: "보관 개수 \(limit)개 초과로 정리")
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
        items[index].text = nil
        thumbnails[item.id] = nil
        save()
    }

    func setNote(_ item: CaptureItem, _ note: String?) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].note = trimmed?.isEmpty == false ? trimmed : nil
        save()
    }

    /// 인식한 글자를 저장한다. 화면을 다시 그릴 필요가 없어 알림은 보내지 않는다.
    func setText(_ id: UUID, _ text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = text
        save(notify: false)
    }

    /// 인식해 둔 글자를 모두 지운다(설정에서 글자 검색을 끄거나 지우기를 누를 때).
    func clearAllText() {
        for index in items.indices { items[index].text = nil }
        save(notify: false)
    }

    /// 아직 글자를 인식하지 않은 캡처를 최근 것부터 하나씩, 사이사이 쉬면서 인식해 둔다(검색용).
    /// 설정에서 글자 검색을 끄면 하지 않는다.
    func indexText(after delay: TimeInterval = 0) {
        guard !isIndexing, AppSettings.shared.textSearch else { return }
        isIndexing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.indexNext() }
    }

    private func indexNext() {
        guard AppSettings.shared.textSearch, let item = items.first(where: { $0.text == nil }), let image = image(for: item) else {
            isIndexing = false
            return
        }
        Task { @MainActor in
            let text = await TextRecognizer.recognize(image)
            self.setText(item.id, text)
            // 한꺼번에 CPU를 쓰지 않게 다음 캡처까지 잠깐 쉰다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.indexNext() }
        }
    }

    private var isIndexing = false

    func setKept(_ item: CaptureItem, _ kept: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isKept = kept
        if !kept { prune() }
        save()
    }

    /// 모든 캡처를 지운다. `keepKept`이면 ★ 고정한 캡처는 남긴다. 지운 개수를 돌려준다.
    @discardableResult
    func removeAll(keepKept: Bool) -> Int {
        let doomed = items.filter { !(keepKept && $0.isKept) }
        for item in doomed { delete(item, reason: keepKept ? "모두 닫기(고정 제외)" : "모두 닫기") }
        items.removeAll { item in doomed.contains { $0.id == item.id } }
        save()
        return doomed.count
    }

    func remove(_ item: CaptureItem) {
        items.removeAll { $0.id == item.id }
        delete(item, reason: "탭 삭제")
        save()
    }

    func image(for item: CaptureItem) -> CGImage? { load(url(for: item)) }

    /// 다시 고칠 수 있는 형태: 원본과 표시. 표시 없이 저장된 캡처는 그 이미지 그대로.
    func editable(for item: CaptureItem) -> (image: CGImage, annotations: [Annotation])? {
        if let original = load(originalURL(for: item)), let annotations = pendingAnnotations[item.id] ?? loadAnnotations(item) {
            return (original, annotations)
        }
        return image(for: item).map { ($0, []) }
    }

    private var pendingAnnotations: [UUID: [Annotation]] = [:]

    private func loadAnnotations(_ item: CaptureItem) -> [Annotation]? {
        guard let data = try? Data(contentsOf: annotationsURL(for: item)) else { return nil }
        return try? JSONDecoder().decode([Annotation].self, from: data)
    }

    func thumbnail(for item: CaptureItem) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        let cg: CGImage?
        if let image = pending[url(for: item)] {
            cg = Self.downscale(image, maxPixel: 400)
        } else if let source = CGImageSourceCreateWithURL(url(for: item) as CFURL, nil) {
            cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 400,
            ] as CFDictionary)
        } else {
            cg = nil
        }
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails[item.id] = image
        return image
    }

    private static func downscale(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let ratio = min(1, CGFloat(maxPixel) / CGFloat(max(image.width, image.height)))
        let w = max(1, Int(CGFloat(image.width) * ratio)), h = max(1, Int(CGFloat(image.height) * ratio))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    private func load(_ url: URL) -> CGImage? {
        if let image = pending[url] { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func writeEditable(_ item: CaptureItem, original: CGImage?, annotations: [Annotation]) {
        let originalURL = originalURL(for: item), annotationsURL = annotationsURL(for: item)
        if let original, !annotations.isEmpty, let data = try? JSONEncoder().encode(annotations) {
            write(original, to: originalURL)
            pendingAnnotations[item.id] = annotations
            io.async {
                try? data.write(to: annotationsURL, options: .atomic)
                DispatchQueue.main.async { [weak self] in self?.pendingAnnotations[item.id] = nil }
            }
        } else {
            pending[originalURL] = nil
            pendingAnnotations[item.id] = nil
            io.async {
                try? FileManager.default.removeItem(at: originalURL)
                try? FileManager.default.removeItem(at: annotationsURL)
            }
        }
    }

    /// 캡처 파일을 지운다. 지운 이유를 기록해 두어, 캡처가 사라졌을 때 원인을 찾을 수 있게 한다.
    private func delete(_ item: CaptureItem, reason: String) {
        EventLog.write("삭제 \(item.id.uuidString) (\(item.width)×\(item.height), \(item.isKept ? "고정" : "보통")) — \(reason)")
        let urls = [url(for: item), originalURL(for: item), annotationsURL(for: item)]
        for url in urls { pending[url] = nil }
        pendingAnnotations[item.id] = nil
        thumbnails[item.id] = nil
        io.async { for url in urls { try? FileManager.default.removeItem(at: url) } }
    }

    private func write(_ image: CGImage, to url: URL) {
        pending[url] = image
        io.async {
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
            DispatchQueue.main.async { [weak self] in
                // 그 사이에 같은 자리에 새 이미지를 썼으면 그대로 둔다.
                if self?.pending[url] === image { self?.pending[url] = nil }
            }
        }
    }

    private func save(notify: Bool = true) {
        if let data = try? JSONEncoder().encode(items) {
            let indexURL = indexURL
            io.async { try? data.write(to: indexURL, options: .atomic) }
        }
        if notify { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }

    /// 밀린 파일 쓰기를 모두 끝낼 때까지 기다린다(앱을 끝낼 때, 점검할 때).
    func flush() { io.sync {} }
}

/// 캡처 삭제처럼 나중에 원인을 찾을 때 필요한 일을 기록한다. 256KB가 넘으면 앞쪽 절반을 버린다.
enum EventLog {
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Grabby/events.log")

    /// 점검(--self-test) 중에는 실제 기록 파일을 건드리지 않는다.
    nonisolated(unsafe) static var isEnabled = true

    static func write(_ message: String) {
        guard isEnabled else { return }
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) [\(ProcessInfo.processInfo.processIdentifier)] \(message)\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 256_000,
           let text = try? String(contentsOf: url, encoding: .utf8) {
            try? String(text.suffix(text.count / 2)).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

enum Clipboard {
    /// 클립보드에 있는 이미지와 배율(픽셀 수 / 포인트 수). 이미지가 없으면 nil.
    static func image() -> (image: CGImage, scale: CGFloat)? {
        let pasteboard = NSPasteboard.general
        guard let nsImage = NSImage(pasteboard: pasteboard) else { return nil }
        var scale: CGFloat = 1
        if let rep = nsImage.representations.compactMap({ $0 as? NSBitmapImageRep }).first, rep.size.width > 0 {
            scale = max(1, (CGFloat(rep.pixelsWide) / rep.size.width).rounded())
        }
        var rect = CGRect(origin: .zero, size: nsImage.size)
        guard let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (cg, scale)
    }

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
