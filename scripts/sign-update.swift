// 앱 안 업데이트에 쓰는 Ed25519 서명 도구. Apple 인증서와는 상관없다.
//
//   swift scripts/sign-update.swift keygen        새 키를 만들고 공개 키를 출력한다(한 번만)
//   swift scripts/sign-update.swift public        저장된 키의 공개 키를 출력한다
//   swift scripts/sign-update.swift sign 파일     파일.sig(서명, base64)를 만든다
//
// 비밀 키는 저장소 밖 ~/.config/grabby/update-signing.key에 둔다(GRABBY_UPDATE_KEY로 바꿀 수 있음).
// 이 키를 잃어버리면 이미 설치된 앱은 새 버전을 자동으로 받지 못하니 따로 백업해 둔다.
import CryptoKit
import Foundation

let keyURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GRABBY_UPDATE_KEY"]
    ?? NSHomeDirectory() + "/.config/grabby/update-signing.key")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOf: keyURL, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("서명 키를 읽지 못했습니다: \(keyURL.path)") }
    return key
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "keygen":
    if FileManager.default.fileExists(atPath: keyURL.path) { fail("이미 키가 있습니다: \(keyURL.path)") }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    FileManager.default.createFile(atPath: keyURL.path, contents: key.rawRepresentation.base64EncodedData(),
                                   attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard args.count == 2, let path = args.last else { fail("사용법: sign 파일") }
    guard let data = FileManager.default.contents(atPath: path) else { fail("파일을 읽지 못했습니다: \(path)") }
    let signature = try loadKey().signature(for: data)
    try signature.base64EncodedString().write(toFile: path + ".sig", atomically: true, encoding: .utf8)
    print(path + ".sig")
default:
    fail("사용법: keygen | public | sign 파일")
}
