import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 이미지를 파일로 저장하는 창. 마지막으로 저장한 폴더를 기억한다.
@MainActor
enum ImageSaver {
    private static let folderKey = "lastSaveFolder"

    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    /// 저장 창을 띄운다. 끝나면(저장했든 취소했든) `completion`을 부른다.
    static func save(_ image: CGImage, scale: CGFloat, date: Date = Date(), completion: (() -> Void)? = nil) {
        let panel = NSSavePanel()
        panel.title = "이미지 저장"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "Grabby \(nameFormatter.string(from: date)).png"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let path = UserDefaults.standard.string(forKey: folderKey) {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            defer { completion?() }
            guard response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: folderKey)
            if write(image, scale: scale, to: url) {
                Toast.show("저장했어요 · \(url.lastPathComponent)")
            } else {
                let alert = NSAlert()
                alert.messageText = "저장하지 못했어요"
                alert.informativeText = url.path
                alert.runModal()
            }
        }
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
