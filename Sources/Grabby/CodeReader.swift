import AppKit
import Vision

/// 이미지 속 QR 코드(와 바코드)를 읽는다. 모두 이 Mac 안에서 처리한다.
enum CodeReader {
    /// 찾은 값들. 위에서 아래, 왼쪽에서 오른쪽 순서이고 같은 값은 한 번만 넣는다.
    static func read(_ image: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                try? VNImageRequestHandler(cgImage: image).perform([request])
                let found = (request.results ?? [])
                    .sorted { a, b in
                        // Vision 좌표는 왼쪽 아래 원점이라, y가 클수록 위에 있다.
                        abs(a.boundingBox.midY - b.boundingBox.midY) > 0.05
                            ? a.boundingBox.midY > b.boundingBox.midY : a.boundingBox.midX < b.boundingBox.midX
                    }
                    .compactMap { $0.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                var seen = Set<String>()
                continuation.resume(returning: found.filter { seen.insert($0).inserted })
            }
        }
    }

    /// 브라우저로 열어도 되는 웹 주소면 URL. http·https만 연다(다른 앱을 실행하는 주소나 파일 주소는 열지 않는다).
    static func webURL(_ value: String) -> URL? {
        guard !value.contains(where: { $0.isWhitespace }), let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// 읽은 값을 복사하고, 링크 하나면 설정에 따라 브라우저로 연다.
    @MainActor
    static func handle(_ values: [String]) {
        guard let first = values.first else {
            Toast.show(L("QR 코드를 찾지 못했어요"))
            return
        }
        Clipboard.copy(text: values.joined(separator: "\n"))
        if values.count > 1 {
            Toast.show(L("QR 코드 %ld개를 읽어 복사했어요", values.count))
        } else if AppSettings.shared.openCodeLinks, let url = webURL(first) {
            NSWorkspace.shared.open(url)
            Toast.show(L("QR 링크를 열었어요 · %@", url.host ?? first))
        } else {
            Toast.show(L("QR 값을 복사했어요 · %@", String(first.prefix(60))))
        }
    }
}
