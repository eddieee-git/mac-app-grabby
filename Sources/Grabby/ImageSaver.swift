import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 이미지를 파일로 저장한다. 설정에 따라 저장 창을 띄우거나 기본 폴더에 바로 저장한다.
@MainActor
enum ImageSaver {
    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    /// 끝나면(저장했든 취소했든) `completion`을 부른다.
    static func save(_ image: CGImage, scale: CGFloat, date: Date = Date(), completion: (() -> Void)? = nil) {
        let settings = AppSettings.shared
        let name = "Grabby \(nameFormatter.string(from: date))"
        let ext = settings.saveFormat.fileExtension

        if settings.saveWithoutPanel {
            try? FileManager.default.createDirectory(at: settings.saveFolder, withIntermediateDirectories: true)
            finish(image, scale: scale, to: uniqueURL(in: settings.saveFolder, name: name, ext: ext))
            completion?()
            return
        }

        let panel = NSSavePanel()
        panel.title = L("이미지 저장")
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "\(name).\(ext)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = settings.saveFolder
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            defer { completion?() }
            guard response == .OK, let url = panel.url else { return }
            finish(image, scale: scale, to: url)
        }
    }

    private static func finish(_ image: CGImage, scale: CGFloat, to url: URL) {
        if write(image, scale: scale, to: url) {
            Toast.show(L("저장했어요 · %@", url.lastPathComponent))
        } else {
            let alert = NSAlert()
            alert.messageText = L("저장하지 못했어요")
            alert.informativeText = url.path
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// 같은 이름이 있으면 " 2", " 3"을 붙인다.
    private static func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        var url = folder.appendingPathComponent("\(name).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(index).\(ext)")
            index += 1
        }
        return url
    }

    /// 확장자가 jpg/jpeg면 JPEG, 나머지는 PNG로 쓴다. 해상도 정보(DPI)를 넣어 화면에서 보던 크기로 열리게 한다.
    private static func write(_ image: CGImage, scale: CGFloat, to url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let type: UTType = ext == "jpg" || ext == "jpeg" ? .jpeg : .png
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale]
        if type == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
