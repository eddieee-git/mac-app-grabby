# Grabby

필요한 기능만 담은 macOS 메뉴바 화면 캡처 앱.

## 기능

- **⌃⌘1** 영역 캡처: 화면이 멈추면 드래그로 영역을 고르고, 그 자리에서 바로 편집한다.
- **⌃⌘2** 마지막 영역 다시 캡처: 직전에 고른 영역을 편집 없이 바로 찍어 복사한다.
- 캡처는 자동으로 클립보드에 복사되고, 원래 쓰던 앱으로 돌아가므로 바로 ⌘V로 붙여 넣을 수 있다.
- 편집 도구: 화살표(A), 네모(R), 텍스트(T), 형광펜(H), 모자이크(M), 색 6가지, 되돌리기(⌘Z). Shift를 누르면 화살표는 45도, 네모는 정사각형으로 맞춰진다.
- 편집 중 ↩ 또는 ⌘C로 확정, Esc로 취소.
- **보관함**: 최근 100개 캡처를 썸네일 목록으로 보관한다. 다시 복사(⌘C 또는 더블클릭), 이어서 편집, 다른 앱으로 끌어다 놓기, 삭제(⌫)를 할 수 있다.
  캡처 파일은 `~/Library/Application Support/Grabby/Captures`에 저장된다.

## 빌드

Xcode 없이 Command Line Tools만으로 빌드한다. Apple 실리콘, macOS 14 이상.

```bash
./scripts/build-app.sh
cp -R build/Grabby.app /Applications/
```

처음 캡처할 때 화면 기록 권한을 요청한다. 시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 기록에서 Grabby를 켠 뒤 앱을 다시 실행한다.

아이콘을 바꾸려면 `scripts/make-icon.swift`를 고친 뒤 `swift scripts/make-icon.swift`를 실행한다.
