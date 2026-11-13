import AppKit

/// 설정에서 켠 경우에만 GitHub에서 최신 릴리스 번호를 한 번 확인한다.
/// 보내는 것은 공개 API 요청 하나뿐이고, 저장소가 비공개거나 인터넷이 없으면 조용히 넘어간다.
@MainActor
enum UpdateChecker {
    static let latestURL = URL(string: "https://api.github.com/repos/eddieee-git/mac-app-grabby/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/eddieee-git/mac-app-grabby/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"

    /// 새 릴리스: 버전과, 있으면 내려받을 dmg 주소와 GitHub가 알려 준 SHA-256.
    struct Release: Equatable {
        let version: String
        let dmg: URL?
        let sha256: String?
        /// dmg와 함께 올린 `.sig`(Ed25519 서명). 없으면 앱 안에서 설치하지 않는다.
        var signature: URL? = nil
    }

    /// 확인할 주소. 디버그 빌드에서는 `-updateFeed <주소>`로 바꿔 점검할 수 있다.
    private static var feedURL: URL {
        #if DEBUG
        if let custom = UserDefaults.standard.string(forKey: "updateFeed"), let url = URL(string: custom) { return url }
        #endif
        return latestURL
    }

    /// 새 버전이 있으면 그 릴리스를 돌려준다. 하루에 한 번만 묻는다(force면 바로).
    static func check(force: Bool = false, completion: @escaping @MainActor (Release?) -> Void) {
        let defaults = UserDefaults.standard
        if !force, let last = defaults.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 {
            completion(nil)
            return
        }
        defaults.set(Date(), forKey: lastCheckKey)
        var request = URLRequest(url: feedURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Grabby", forHTTPHeaderField: "User-Agent")
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        URLSession.shared.dataTask(with: request) { data, response, _ in
            var newer: Release?
            let ok = (response as? HTTPURLResponse).map { $0.statusCode == 200 } ?? (data != nil)
            if ok, let data, let release = parse(data), isNewer(release.version, than: current) { newer = release }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(newer) } }
        }.resume()
    }

    /// GitHub 릴리스 응답에서 버전과 첫 dmg 첨부 파일을 읽는다.
    nonisolated static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        let url = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
        var sha: String?
        if let digest = dmg?["digest"] as? String, digest.hasPrefix("sha256:") { sha = String(digest.dropFirst(7)).lowercased() }
        let sigName = (dmg?["name"] as? String).map { $0 + ".sig" }
        let sig = assets.first { $0["name"] as? String == sigName }
        let sigURL = (sig?["browser_download_url"] as? String).flatMap(URL.init(string:))
        return Release(version: version, dmg: url, sha256: sha, signature: sigURL)
    }

    /// "0.10.0"이 "0.9.1"보다 새 것이라고 판단하도록 숫자 단위로 비교한다.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
