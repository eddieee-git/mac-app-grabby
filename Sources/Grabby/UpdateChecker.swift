import AppKit

/// 설정에서 켠 경우에만 GitHub에서 최신 릴리스 번호를 한 번 확인한다.
/// 보내는 것은 공개 API 요청 하나뿐이고, 저장소가 비공개거나 인터넷이 없으면 조용히 넘어간다.
@MainActor
enum UpdateChecker {
    static let latestURL = URL(string: "https://api.github.com/repos/eddieee-git/Grabby/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/eddieee-git/Grabby/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"

    /// 새 버전이 있으면 그 버전 문자열을 돌려준다. 하루에 한 번만 묻는다(force면 바로).
    static func check(force: Bool = false, completion: @escaping @MainActor (String?) -> Void) {
        let defaults = UserDefaults.standard
        if !force, let last = defaults.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 {
            completion(nil)
            return
        }
        defaults.set(Date(), forKey: lastCheckKey)
        var request = URLRequest(url: latestURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Grabby", forHTTPHeaderField: "User-Agent")
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        URLSession.shared.dataTask(with: request) { data, response, _ in
            var newer: String?
            if (response as? HTTPURLResponse)?.statusCode == 200, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                if isNewer(version, than: current) { newer = version }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(newer) } }
        }.resume()
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
