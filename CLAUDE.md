# Grabby 개발 메모

macOS 메뉴바 화면 캡처 앱. Swift Package 실행 파일 하나로, Xcode 없이 Command Line Tools만으로 빌드한다.
Apple 실리콘, macOS 14 이상. 저장소: `eddieee-git/mac-app-grabby` (공개).

## 지켜야 할 것

- **Apple 계정이 필요한 기능은 만들지 않는다.** iCloud 동기화, 공증(notarization), Developer ID 서명 등. 그래서 앱은 임시(ad-hoc) 서명이고, dmg로 처음 열면 Gatekeeper 경고가 뜬다.
- **다른 캡처 앱의 이름이나 그 앱을 분석한 내용을 공개 문서·커밋 메시지에 쓰지 않는다.** (코드 안의 겹침 경고용 번들 ID 목록은 예외)
- **스크린샷에 개인 내용이 나오지 않게 한다.** 데모 문서를 띄워서 찍는다.
- 타이머 알람·매일 알람 같은 시계 기능은 별도 앱(Clocky)의 몫이다. Grabby의 타이머는 "몇 초 뒤 캡처"뿐이다.
- 사용자 문구는 한국어로 쓰고 영어 번역을 함께 넣는다. 말투는 "~해요".

## 명령

```bash
./scripts/test.sh                       # 빌드 + 자체 점검(--self-test). 실제 보관함·설정은 건드리지 않음
./scripts/build-app.sh                  # build/Grabby.app + build/Grabby-<버전>.dmg (릴리스 빌드)
GRABBY_DEBUG=1 ./scripts/build-app.sh   # 디버그 빌드, dmg 없음. 점검용 실행 인자가 동작함
./scripts/release.sh                    # 점검 → 빌드 → 태그 push → gh release create (dmg 첨부)
./scripts/make-signing-cert.sh          # (선택) 이 Mac 전용 서명 인증서. 다시 빌드해도 화면 기록 권한 유지
swift scripts/sign-update.swift public  # 업데이트 서명 키의 공개 키 출력 (keygen | public | sign 파일)
```

디버그 빌드 전용 실행 인자:
- `-showInDock YES`: 일반 앱처럼 Dock에 보임(화면 자동화 도구로 점검할 때 필요)
- `-captureFolder <경로>`: 다른 보관함 사용
- `-updateFeed <주소>`: 업데이트 확인 주소를 바꿈(`file://…json`도 됨)
- `-autoInstallUpdate YES`: 새 버전을 찾으면 묻지 않고 설치

## 릴리스 순서

1. `Resources/Info.plist`의 `CFBundleShortVersionString`(그리고 `CFBundleVersion` +1)을 올린다.
2. `docs/releases/v<버전>.md`에 릴리스 노트를 쓴다(이전 노트 형식 참고: 설치와 업데이트 → 새 기능 → 바뀐 점 → 알려진 제한).
3. README 두 개(`README.md`, `README.en.md`)와 변경 기록 두 개(`CHANGELOG.md`, `CHANGELOG.en.md`, "릴리스 전"을 날짜로)를 함께 고친다. 릴리스 노트에는 `## English` 부분을 넣는다(SHA-256은 `release.sh`가 붙인다).
4. 커밋하고 `main`을 push한 뒤 `./scripts/release.sh`.
5. 확인: `gh api repos/eddieee-git/mac-app-grabby/releases/latest --jq '.tag_name, .assets[].digest'`의 digest가 `shasum -a 256 build/Grabby-<버전>.dmg`와 같은지.

앱 안의 업데이트는 GitHub 최신 릴리스의 첫 `.dmg` 첨부와, 같은 이름에 `.sig`를 붙인 Ed25519 서명 파일을 쓴다. 릴리스에는 dmg 하나와 그 `.sig`를 올리고, dmg 안 앱 이름은 `Grabby.app`, 버전은 태그와 같아야 한다.

**업데이트 서명 키**
- 비밀 키는 저장소 밖 `~/.config/grabby/update-signing.key`(`GRABBY_UPDATE_KEY`로 바꿀 수 있음)에 있다. 공개 키는 `Updater.publicKey`에 들어 있다.
- `build-app.sh`가 키가 있으면 `build/Grabby-<버전>.dmg.sig`를 만들고, `release.sh`는 `.sig`가 없으면 멈춘다.
- **키를 잃어버리면 이미 설치된 앱은 새 버전을 자동으로 받지 못한다.** 따로 백업해 둔다. 키를 바꾸면 그 전 버전 사용자는 dmg로 한 번 직접 업데이트해야 한다.
- 0.3.1은 서명 대신 GitHub의 SHA-256만 확인하는 버전이라, 0.3.1 → 다음 버전도 메뉴에서 받을 수 있다.

## 구조 (Sources/Grabby)

| 파일 | 하는 일 |
|---|---|
| `main.swift` | 시작점. `--self-test`면 점검만 돌리고 끝냄 |
| `AppDelegate.swift` | 메뉴바 메뉴, 단축키 동작, 캡처 끝난 뒤 처리(`finishCapture`: 복사/저장/띄우기/OCR/QR/꾸미기/탭에만 남기기), 타이머, 업데이트 메뉴 |
| `CaptureOverlay.swift` | 캡처 화면(`CaptureSession`, `OverlayWindow`, `OverlayView`). 영역·창 고르기, 도구 막대, 키 처리, Esc 처리 |
| `AnnotationCanvas.swift` / `EditToolbar.swift` | 그리기 도구와 표시, 도구 막대 |
| `ScreenCapturer.swift` | ScreenCaptureKit 캡처와 화면 기록 권한 안내 |
| `CaptureStore.swift` / `CaptureTab.swift` | 탭 보관함(`~/Library/Application Support/Grabby/Captures`), 정리, 글자 인식 검색 |
| `LibraryWindow*.swift`, `LibraryActions.swift` | 탭 창 |
| `PinWindow.swift`, `Beautifier.swift`, `ImageSaver.swift` | 화면에 띄우기, 꾸며서 복사, 파일 저장 |
| `CodeReader.swift` | QR·바코드 읽기(Vision). 웹 주소(http/https)만 브라우저로 엶 |
| `HotKey.swift` | Carbon 전역 단축키, `HotKeyAction`, 기본값(⇧⌘)과 ⌃⌘ 묶음 |
| `SettingsWindow.swift` | `AppSettings`(UserDefaults)와 설정 창(SwiftUI) |
| `UpdateChecker.swift` / `Updater.swift` | 최신 릴리스 확인 / 내려받아 확인(Ed25519 `.sig`·SHA-256·번들 ID·버전·코드 서명) 후 바꿔 넣고 다시 시작. 업데이트 뒤 화면 기록 권한이 풀렸으면 안내 |
| `Localization.swift` | `L()`과 영어 사전 |
| `Toast.swift`, `Countdown.swift`, `Feedback.swift`, `WelcomeWindow.swift` | 알림, 타이머 숫자, 캡처 반짝임·소리, 시작 안내 |
| `SelfTest.swift` | 자체 점검 묶음 |

## 규칙과 함정

- **번역**: 한국어 문구를 키로 `L("…")`을 쓰고, `Localization.swift`의 `// 새 기능` 아래에 영어를 더한다. **같은 키가 두 번 들어가면 실행 중에 죽는다.** 고친 뒤 중복을 확인한다:
  ```bash
  python3 -c "import re,collections;s=open('Sources/Grabby/Localization.swift').read();k=re.findall(r'^\s*\"((?:[^\"\\\\]|\\\\.)*)\"\s*:',s,re.M);print([x for x,c in collections.Counter(k).items() if c>1])"
  ```
  안 쓰게 된 문구는 사전에서도 지운다.
- **설정 추가**: `AppSettings`에 `@Published var x: Bool { didSet { defaults.set(...) } }`, `init`에서 `defaults.object(forKey:) as? Bool ?? 기본값`으로 읽는다. `init` 안의 대입은 `didSet`을 부르지 않으므로, 꼭 저장해야 하는 값(예: 단축키)은 직접 `defaults.set` 한다.
- **단축키 추가**: `HotKeyAction`에 더하고 기본값을 정한다. 이미 쓰던 사용자의 단축키가 모두 ⌃⌘면 새 동작도 ⌃⌘로 맞추는 이전 처리가 `AppSettings.init`에 있다.
- **캡처 화면**은 포커스를 빼앗지 않는 `NSPanel`이다. 끝나면 `returnToPreviousApp()`으로 원래 앱에 돌려준다.
- **점검(self-test)** 은 `EventLog`를 끄고 임시 보관함을 쓴다. 새 기능에는 `SelfTest.swift`에 묶음을 더하고 목록에 등록한다.
- **강화 런타임**: `build-app.sh`가 `--options runtime`으로 서명한다. 동적 라이브러리를 새로 쓰게 되면 이 때문에 막히는지 확인한다.
- **업데이트 점검**: 가짜 릴리스로 끝까지 시험할 수 있다. 버전을 올린 릴리스 dmg와 `.sig`를 만들고, 버전을 낮춘 디버그 앱을 임시 폴더에 복사한 뒤, `{"tag_name":"v…","assets":[{"name":"Grabby-….dmg","browser_download_url":"file://…","digest":"sha256:…"},{"name":"Grabby-….dmg.sig","browser_download_url":"file://….sig"}]}` 피드로 `-updateFeed file://… -autoInstallUpdate YES -checkUpdates YES -lastUpdateCheck '<date>2000-01-01T00:00:00Z</date>'`를 주고 실행한다. 점검용 앱은 실제 앱과 같은 UserDefaults를 쓰므로, 끝나면 실제 앱을 다시 깔아 둔다.
- **이 Mac 설정**: 단축키는 ⌃⌘ 묶음을 쓴다(⇧⌘3·4·5는 macOS 스크린샷과 겹침).
