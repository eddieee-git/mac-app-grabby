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
