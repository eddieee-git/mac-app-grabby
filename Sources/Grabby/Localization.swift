import Foundation

/// 앱 화면 언어. 설정에서 고르면 바로 바뀐다.
enum AppLanguage: String, CaseIterable {
    case korean = "ko"
    case english = "en"

    /// 언어 이름은 그 언어로 쓴다.
    var title: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    /// 처음에는 Mac의 언어를 따르고, 한국어가 아니면 영어로 시작한다.
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english
    }
}

enum Localization {
    static let key = "language"

    /// 바뀌면 `didChange`를 알린다. 메뉴와 창은 알림을 받아 다시 만든다.
    static var language: AppLanguage = UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init) ?? .systemDefault {
        didSet {
            guard language != oldValue else { return }
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
    static let didChange = Notification.Name("GrabbyLanguageDidChange")

    /// 화면 문구는 한국어를 열쇠로 쓰고, 영어일 때 이 표에서 바꾼다. 표에 없으면 한국어가 그대로 나온다.
    static let english: [String: String] = [
        // 메뉴
        "영역 캡처": "Capture Area",
        "마지막 영역 다시 캡처": "Capture Last Area Again",
        "화이트보드": "Whiteboard",
        "캡처 창 열기": "Open Capture Window",
        "설정…": "Settings…",
        "Grabby 종료": "Quit Grabby",
        "편집": "Edit",
        "실행 취소": "Undo",
        "오려두기": "Cut",
        "복사": "Copy",
        "붙이기": "Paste",
        "전체 선택": "Select All",
        "창 닫기": "Close Window",
        "저장…": "Save…",

        // 알림
        "복사했어요 · ⌘V로 붙여 넣기": "Copied · Paste with ⌘V",
        "복사했어요": "Copied",
        "선택한 부분을 복사했어요": "Copied the selection",
        "저장했어요 · %@": "Saved · %@",
        "저장하지 못했어요": "Couldn't save",
        "캡처하지 못했어요": "Couldn't capture",
        "화면 기록 권한이 필요해요": "Screen Recording permission needed",
        "시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 기록에서 Grabby를 켠 뒤, Grabby를 다시 실행해 주세요.":
            "Turn on Grabby in System Settings > Privacy & Security > Screen & System Audio Recording, then restart Grabby.",
        "시스템 설정 열기": "Open System Settings",
        "닫기": "Close",
        "이 캡처를 삭제할까요?": "Delete this capture?",
        "삭제한 캡처는 되돌릴 수 없어요.": "Deleted captures can't be restored.",
        "삭제": "Delete",
        "취소": "Cancel",
        "다시 묻지 않기": "Don't ask again",

        // 편집 도구
        "부분 선택 (V) · ⌘C로 선택한 부분만 복사": "Select Part (V) · ⌘C copies only the selection",
        "화살표 (A)": "Arrow (A)",
        "네모 (R)": "Rectangle (R)",
        "자유그리기 (P)": "Pen (P)",
        "텍스트 (T)": "Text (T)",
        "형광펜 (H)": "Highlighter (H)",
        "모자이크 (M)": "Pixelate (M)",
        "얇게": "Thin",
        "보통": "Medium",
        "굵게": "Thick",
        "선 굵기·글자 크기: %@": "Line width / text size: %@",
        "다시 실행 (⇧⌘Z)": "Redo (⇧⌘Z)",
        "다시 실행": "Redo",
        "되돌리기 (⌘Z)": "Undo (⌘Z)",
        "취소 (Esc)": "Cancel (Esc)",
        "파일로 저장 (⌘S) · 복사하고 탭에도 추가": "Save to File (⌘S) · also copies and adds a tab",
        "복사하고 탭에 추가 (↩ 또는 ⌘C)": "Copy and Add Tab (↩ or ⌘C)",
        "완료": "Done",
        "안에서 드래그해 일부만 고르기 · 도구로 그리기 · 손잡이·방향키로 영역 조정 · ↩/⌘C 복사 · ⌘S 저장 · Esc 취소":
            "Drag inside to select a part · Draw with tools · Adjust with handles or arrow keys · ↩/⌘C Copy · ⌘S Save · Esc Cancel",

        // 탭 창
        "아직 캡처가 없어요.\n메뉴바의 영역 캡처나 단축키로 화면을 캡처해 보세요.":
            "No captures yet.\nCapture the screen from the menu bar or with a shortcut.",
        "항상 위에": "Always on Top",
        "창을 항상 위에 두기": "Keep window on top",
        "복사 (⌘C) · 고른 부분이 있으면 그 부분만": "Copy (⌘C) · only the selection if there is one",
        "파일로 저장 (⌘S) · 고른 부분이 있으면 그 부분만": "Save to File (⌘S) · only the selection if there is one",
        "Finder에서 보기": "Show in Finder",
        "삭제 (⌫)": "Delete (⌫)",
        "이미지 저장": "Save Image",

        // 설정
        "기본 색": "Default Color",
        "기본 선 굵기": "Default Line Width",
        "마지막에 쓴 색과 굵기를 기본값으로 기억": "Remember the last used color and width",
        "캡처할 때 시작 도구": "Starting Tool for Captures",
        "화이트보드 시작 도구": "Starting Tool for Whiteboard",
        "부분 선택": "Select Part",
        "화살표": "Arrow",
        "네모": "Rectangle",
        "자유그리기": "Pen",
        "텍스트": "Text",
        "형광펜": "Highlighter",
        "모자이크": "Pixelate",
        "Grabby 설정": "Grabby Settings",
        "설정": "Settings",
        "일반": "General",
        "언어": "Language",
        "테마": "Theme",
        "라이트": "Light",
        "다크": "Dark",
        "시스템": "System",
        "로그인 시 실행": "Launch at Login",
        "탭을 삭제하기 전에 확인": "Confirm before deleting a tab",
        "저장": "Saving",
        "기본 저장 폴더": "Default Folder",
        "변경…": "Change…",
        "형식": "Format",
        "저장 창 없이 기본 폴더에 바로 저장": "Save straight to the default folder without asking",
        "폴더 선택": "Choose",
        "단축키": "Shortcuts",
        "등록하지 못함": "Not registered",
        "키를 누르세요": "Press keys",
        "없음": "None",
        "단축키 지우기": "Clear shortcut",
        "다른 캡처 앱과 겹치면 먼저 등록한 앱이 키를 받아요. Esc로 입력 취소.":
            "If another capture app uses the same keys, the app that registered first gets them. Esc cancels.",
        "기본값으로": "Restore Defaults",
        "⌘, ⌃, ⌥ 중 하나와 함께 누르세요.": "Press together with ⌘, ⌃ or ⌥.",
        "%@에서 쓰는 단축키예요.": "Already used by %@.",
        // 새 기능
        "%ld초 뒤": "In %ld Seconds",
        "%ld초 뒤에 캡처해요": "Capturing in %ld s",
        "1. 화면 기록 권한": "1. Screen Recording Permission",
        "2. 단축키": "2. Shortcuts",
        "3. 쓰는 방법": "3. How to Use",
        "?를 다시 누르면 닫혀요": "Press ? again to close",
        "C 색 복사 · F 전체 화면 · 클릭 창 · ? 도움말": "C color · F full screen · click window · ? help",
        "GitHub 저장소": "GitHub Repository",
        "Grabby 시작 안내": "Getting Started with Grabby",
        "Grabby에 오신 걸 환영해요": "Welcome to Grabby",
        "• 고른 자리에서 바로 그리고, ↩로 복사해요. 원래 앱에서 바로 ⌘V로 붙여 넣으면 돼요.": "• Draw right where you selected and press ↩ to copy. Then paste with ⌘V in your app.",
        "• 드래그해서 영역을 고르거나, 클릭해서 창을 골라요.": "• Drag to select an area, or click to select a window.",
        "• 캡처 중에 ?를 누르면 모든 단축키를 볼 수 있어요.": "• Press ? while capturing to see every shortcut.",
        "• 캡처는 Grabby 창에 탭으로 쌓여요. 나중에 다시 고치거나 복사할 수 있어요.": "• Captures pile up as tabs in the Grabby window, ready to edit or copy later.",
        "가운데 픽셀 색 복사": "Copy center pixel color",
        "고르기 · 끌어서 옮기기 · ⌫ 지우기 · 더블클릭 텍스트 고치기": "Select · drag to move · ⌫ delete · double-click to edit text",
        "권한 켜기": "Turn On",
        "글자 복사": "Copy text",
        "글자·메모 검색": "Search text & notes",
        "꾸며서 복사": "Copy styled",
        "꾸며서 복사 (⌘B) · 여백·배경·그림자를 넣어 복사": "Copy Styled (⌘B) · with padding, background and shadow",
        "꾸며서 복사했어요": "Copied with style",
        "꾸미기 배경": "Style Background",
        "꾸미기 여백": "Style Padding",
        "넓게": "Wide",
        "노을": "Sunset",
        "되돌리기 · 다시 실행": "Undo · Redo",
        "드래그": "Drag",
        "마우스 아래 창 고르기": "Select the window under the pointer",
        "마치기": "Finish",
        "메뉴바에 있는 캡처 앱이에요. 찍고, 그리고, 바로 붙여 넣으세요.": "A menu bar capture app. Capture, draw, and paste right away.",
        "메모": "Note",
        "메모 달기 · 탭 이름으로 보이고 검색돼요": "Add Note · shown as the tab name and searchable",
        "바다": "Ocean",
        "방향키": "Arrow keys",
        "버전 %@ (%@)": "Version %@ (%@)",
        "복사하고 탭에 추가": "Copy and add a tab",
        "부분 선택 · 화살표 · 직선 · 네모 · 동그라미 · 자유그리기": "Select part · Arrow · Line · Rectangle · Ellipse · Pen",
        "부분 선택(V)으로 남길 영역을 먼저 고르세요": "First select the area to keep with Select Part (V)",
        "붙여 넣어 새 탭을 만들었어요": "Pasted as a new tab",
        "색 직접 고르기": "Pick a color",
        "설정 열기": "Open Settings",
        "숲": "Forest",
        "시스템 설정에서 Grabby를 켜고, Grabby를 다시 실행해 주세요.": "Turn on Grabby in System Settings, then restart Grabby.",
        "시작 안내": "Getting Started",
        "시작하기": "Get Started",
        "안에서 드래그해 일부만 고르기 · 그린 표시는 눌러서 옮기기·⌫ 지우기 · ↩/⌘C 복사 · Esc 취소 · ? 단축키 도움말": "Drag inside to select a part · Click a mark to move it, ⌫ to delete · ↩/⌘C Copy · Esc Cancel · ? Shortcuts",
        "영역 고르기": "Selecting",
        "영역 옮기기 (⇧ 10px, ⌥ 크기)": "Move area (⇧ 10px, ⌥ resize)",
        "예: 회의 자료, 버그 화면": "e.g. meeting notes, bug screen",
        "자르기 · 부분 선택한 영역만 남겨요": "Crop · keep only the selected part",
        "전체 화면": "Full screen",
        "정보": "About",
        "좁게": "Narrow",
        "캡처 속 글자나 메모로 찾아요": "Find by text in captures or notes",
        "캡처 폴더 열기": "Open Captures Folder",
        "켜져 있어요.": "It's on.",
        "클릭": "Click",
        "클립보드에 이미지가 없어요": "No image on the clipboard",
        "타이머 캡처": "Timed Capture",
        "탭 이름 대신 보이고, 검색할 때 찾을 수 있어요.": "Shown instead of the tab name and found by search.",
        "텍스트 · 번호 · 형광펜 · 모자이크 · 흐리게": "Text · Step · Highlighter · Pixelate · Blur",
        "파일로 저장": "Save to file",
        "표시 클릭": "Click a mark",
        "필요한 기능만 담은 메뉴바 화면 캡처 앱": "A menu bar screen capture app with just what you need",
        "화면에 띄우기": "Pin to screen",
        "화살표·직선 45도, 네모·동그라미 정사각형": "Arrow/line at 45°, square rectangle/circle",
        "회색": "Gray",
        "직선 (L)": "Line (L)",
        "동그라미 (O)": "Ellipse (O)",
        "번호 (N) · 누를 때마다 1, 2, 3…": "Step (N) · 1, 2, 3… with each click",
        "흐리게 (B)": "Blur (B)",
        "직선": "Line",
        "동그라미": "Ellipse",
        "번호": "Step",
        "흐리게": "Blur",
        "%@는 macOS 스크린샷 단축키라 쓸 수 없어요.": "%@ is a macOS screenshot shortcut and can't be used.",
        "%@이(가) 켜져 있어요 · 단축키가 겹치면 설정에서 바꿔 주세요": "%@ is running · Change shortcuts in Settings if they overlap",
        "%@이(가) 켜져 있어요. 같은 단축키를 쓰면 먼저 등록한 앱이 키를 받으니, 겹치지 않게 바꿔 주세요.":
            "%@ is running. If both use the same shortcut, the app that registered first gets it, so pick different keys.",
        "%ld개": "%ld",
        "C 색 복사 · F 전체 화면 · 클릭 창 선택": "C copy color · F full screen · click a window",
        "고정": "Keep",
        "고정 (★) · 보관 개수를 넘어도 지우지 않아요": "Keep (★) · never removed by the capture limit",
        "고정(★)한 캡처는 개수에 넣지 않고 지우지 않아요.": "Kept (★) captures don't count toward the limit and are never removed.",
        "글자 복사 (⌘T) · 이미지 속 글자를 인식해 복사": "Copy Text (⌘T) · recognize and copy text in the image",
        "글자를 복사했어요 · %@": "Copied text · %@",
        "글자를 찾지 못했어요": "No text found",
        "띄운 캡처 모두 닫기": "Close All Pinned Captures",
        "맞춤": "Fit",
        "모눈": "Grid",
        "모든 캡처 보기": "All Captures",
        "무제한": "Unlimited",
        "보관할 캡처 수": "Captures to Keep",
        "복사했어요 · 오래된 캡처 %ld개를 정리했어요": "Copied · Removed %ld old captures",
        "색을 복사했어요 · %@": "Copied color · %@",
        "실제 크기": "Actual Size",
        "실제 크기 (⌘0)": "Actual Size (⌘0)",
        "아직 캡처가 없어요.": "No captures yet.",
        "안에서 드래그해 일부만 고르기 · 그린 표시는 눌러서 옮기기·⌫ 지우기 · 손잡이·방향키로 영역 조정 · ↩/⌘C 복사 · Esc 취소":
            "Drag inside to select a part · Click a mark to move it, ⌫ to delete · Adjust with handles or arrow keys · ↩/⌘C Copy · Esc Cancel",
        "전체 화면 캡처": "Capture Full Screen",
        "줄": "Lines",
        "창에 맞추기 (⌘9)": "Zoom to Fit (⌘9)",
        "축소 (⌘-)": "Zoom Out (⌘-)",
        "칠판": "Chalkboard",
        "캡처할 때 소리": "Play sound when capturing",
        "투명도": "Opacity",
        "화면에 띄우기 (⌘P)": "Pin to Screen (⌘P)",
        "화면에 띄우기 (⌘P) · 복사하고 탭에도 추가": "Pin to Screen (⌘P) · also copies and adds a tab",
        "화이트보드 바탕": "Whiteboard Background",
        "확대 (⌘+)": "Zoom In (⌘+)",
        "흰색": "White",
    ]
}

/// 화면 문구. 한국어 문구를 그대로 넘기면 고른 언어로 돌려준다.
func L(_ korean: String) -> String {
    Localization.language == .korean ? korean : Localization.english[korean] ?? korean
}

/// `%@`가 든 문구.
func L(_ korean: String, _ arguments: CVarArg...) -> String {
    String(format: L(korean), arguments: arguments)
}
