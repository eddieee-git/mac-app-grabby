import AppKit
import CryptoKit

/// 메뉴에서 고르면 새 릴리스의 dmg를 내려받아 지금 앱 자리에 바꿔 넣고 다시 시작한다.
/// 릴리스에 함께 올린 `.sig`(Ed25519 서명)를 앱에 넣은 공개 키로 확인한다. 비밀 키는 개발자만 갖고 있어서,
/// GitHub 계정이나 다운로드 경로가 털려도 다른 파일은 설치하지 않는다. Apple 인증서와는 상관없다(`scripts/sign-update.swift`).
/// 그 밖에 GitHub가 알려 준 SHA-256(있으면), 번들 ID와 버전, 코드 서명도 확인한다.
/// 앱이 직접 내려받은 파일에는 격리 표시가 붙지 않아서, 새 버전을 열 때 Gatekeeper 경고가 뜨지 않는다.
@MainActor
enum Updater {
    private(set) static var isInstalling = false
    static let updatedFromKey = "updatedFromVersion"
    /// `~/.config/grabby/update-signing.key`의 공개 키.
    nonisolated static let publicKey = "vT6+HF0GsqE4tcyOzKYfBj5Mt1+LOchWa7Josi8Jb44="

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 지금 앱을 그 자리에서 바꿀 수 있는지. dmg 안에서 바로 실행 중이거나 폴더에 쓸 수 없으면 안 된다.
    nonisolated static func canReplace(_ app: URL) -> Bool {
        let fm = FileManager.default
        let path = app.standardizedFileURL.path
        return path.hasSuffix(".app") && !path.hasPrefix("/Volumes/")
            && fm.isWritableFile(atPath: app.deletingLastPathComponent().path)
            && fm.isWritableFile(atPath: path)
    }

    /// 내려받아 확인하고, 다시 시작하면서 바꿔 넣는다. 실패하면 지금 앱은 그대로 둔다.
    static func install(_ release: UpdateChecker.Release) async throws {
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }
        let app = Bundle.main.bundleURL
        let identifier = Bundle.main.bundleIdentifier ?? "com.eddieee.Grabby"
        let staged = try await Task.detached(priority: .userInitiated) {
            try await prepare(release, replacing: app, identifier: identifier)
        }.value
        UserDefaults.standard.set(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, forKey: updatedFromKey)
        swapAndRelaunch(staged: staged.app, work: staged.work, destination: app)
    }

    /// 새 버전으로 처음 켜졌으면 한 번 알려 준다.
    static func announceIfUpdated() {
        let defaults = UserDefaults.standard
        guard let from = defaults.string(forKey: updatedFromKey) else { return }
        defaults.removeObject(forKey: updatedFromKey)
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard from != current else { return }
        Toast.show(L("Grabby %@로 업데이트했어요", current))
        // 서명이 바뀐 새 버전을 macOS가 다른 앱으로 보면 화면 기록 권한이 풀린다. 캡처하다 알게 되지 않도록 바로 안내한다.
        if !ScreenCapturer.hasPermission {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ScreenCapturer.requestPermission() }
        }
    }

    // MARK: - 내려받기와 확인

    nonisolated private static func prepare(_ release: UpdateChecker.Release, replacing app: URL,
                                            identifier: String) async throws -> (app: URL, work: URL) {
        guard let dmg = release.dmg, let signatureURL = release.signature else {
            throw Failure(message: L("이 릴리스에는 자동으로 설치할 파일이 없어요."))
        }
        let (downloaded, response) = try await URLSession.shared.download(from: dmg)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure(message: L("내려받지 못했어요 (HTTP %ld)", http.statusCode))
        }
        let (signature, sigResponse) = try await URLSession.shared.data(from: signatureURL)
        if let http = sigResponse as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure(message: L("내려받지 못했어요 (HTTP %ld)", http.statusCode))
        }
        let data = try Data(contentsOf: downloaded, options: .mappedIfSafe)
        guard isSigned(data, signature: signature) else {
            throw Failure(message: L("업데이트 서명이 맞지 않아요. 설치하지 않았어요."))
        }
        if let expected = release.sha256, try sha256(of: downloaded) != expected {
            throw Failure(message: L("내려받은 파일이 릴리스와 달라요. 설치하지 않았어요."))
        }

        // 바꿔 넣을 자리와 같은 디스크에 작업 폴더를 만들어, 마지막 이동이 한 번에 끝나게 한다.
        let fm = FileManager.default
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        var success = false
        defer { if !success { try? fm.removeItem(at: work) } }
        let mount = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", downloaded.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path],
                failure: L("dmg를 열지 못했어요."))
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"], failure: "") }

        let new = mount.appendingPathComponent("Grabby.app")
        let info = NSDictionary(contentsOf: new.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == identifier,
              info?["CFBundleShortVersionString"] as? String == release.version else {
            throw Failure(message: L("dmg 안의 앱이 Grabby %@가 아니에요.", release.version))
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=identifier \"\(identifier)\"", new.path],
                failure: L("새 앱의 서명을 확인하지 못했어요."))

        let staged = work.appendingPathComponent("Grabby.app")
        try run("/usr/bin/ditto", [new.path, staged.path], failure: L("새 앱을 복사하지 못했어요."))
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path], failure: "")
        success = true
        return (staged, work)
    }

    /// `.sig` 내용(base64)이 이 데이터에 대한 우리 키의 서명인지.
    nonisolated static func isSigned(_ data: Data, signature: Data, publicKey: String = publicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let raw = Data(base64Encoded: String(decoding: signature, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return key.isValidSignature(raw, for: data)
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String], failure: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw Failure(message: failure) }
    }

    // MARK: - 바꿔 넣기

    /// 앱이 끝나기를 기다렸다가 옛 앱을 치우고 새 앱을 놓은 뒤 연다. 옮기다 실패하면 옛 앱을 되돌린다.
    private static func swapAndRelaunch(staged: URL, work: URL, destination: URL) {
        let script = """
        while kill -0 "$0" 2>/dev/null; do sleep 0.2; done
        backup="$3/previous.app"
        if /bin/mv "$2" "$backup"; then
            if /bin/mv "$1" "$2"; then /bin/rm -rf "$3"; else /bin/mv "$backup" "$2"; fi
        fi
        /usr/bin/open "$2"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, String(ProcessInfo.processInfo.processIdentifier),
                          staged.path, destination.standardizedFileURL.path, work.path]
        do {
            try task.run()
        } catch {
            try? FileManager.default.removeItem(at: work)
            return
        }
        NSApp.terminate(nil)
    }
}
