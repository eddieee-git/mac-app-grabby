import AppKit
import Vision

/// 캡처했다는 표시: 찍은 영역을 잠깐 하얗게 반짝이고, 설정에 따라 셔터 소리를 낸다.
@MainActor
enum CaptureFeedback {
    private static var flashes: [NSWindow] = []
    private static let sound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
    }()

    /// `rect`는 전역 좌표(왼쪽 아래 원점).
    static func flash(_ rect: CGRect) {
        if AppSettings.shared.captureSound {
            sound?.stop()
            sound?.play()
        }
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = NSColor.white.withAlphaComponent(0.55)
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.orderFrontRegardless()
        flashes.append(window)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            flashes.removeAll { $0 === window }
        })
    }
}

/// 이미지 속 글자 인식. 한국어와 영어를 함께 읽는다.
enum TextRecognizer {
    /// 시간이 걸리므로 백그라운드에서 돌린다.
    static func recognize(_ image: CGImage) async -> String {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ko-KR", "en-US"]
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}
