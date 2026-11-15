import AppKit

/// 공통 업데이트(AppUpdater.swift)에 Grabby 정보를 넣는다. AppUpdater.swift는 mac-app/shared에서 복사해 오므로 여기만 고친다.
extension AppUpdater {
    /// `~/.config/grabby/update-signing.key`의 공개 키 (scripts/sign-update.swift)
    nonisolated static let appPublicKey = "vT6+HF0GsqE4tcyOzKYfBj5Mt1+LOchWa7Josi8Jb44="
    nonisolated static let appSignatureFormat = SignatureFormat.dmg

    static let shared = AppUpdater(.init(
        appName: "Grabby",
        repo: "eddieee-git/mac-app-grabby",
        publicKey: appPublicKey,
        signatureFormat: appSignatureFormat,
        isEnglish: { Localization.language == .english },
        // 0.3.2까지는 "새 버전이 나오면 알려 주기"(기본 끔)였다. 직접 끈 사람만 그대로 끈다.
        legacyAutoCheckKey: "checkUpdates",
        didUpdate: { _ in
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            Toast.show(L("Grabby %@로 업데이트했어요", current))
            // 서명이 바뀐 새 버전을 macOS가 다른 앱으로 보면 화면 기록 권한이 풀린다. 캡처하다 알게 되지 않도록 바로 안내한다.
            if !ScreenCapturer.hasPermission {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ScreenCapturer.requestPermission() }
            }
        }
    ))
}
