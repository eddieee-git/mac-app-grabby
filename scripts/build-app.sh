#!/bin/zsh
# build/Grabby.app을 만든다. Xcode 없이 Command Line Tools만으로 빌드한다.
# Apple 실리콘 Mac 전용이다.
set -e
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

app=build/Grabby.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64-apple-macosx/release/Grabby "$app/Contents/MacOS/Grabby"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# 개발자 인증서가 없으므로 임시 서명을 한다. 서명 조건을 번들 ID로 지정해서
# 다시 빌드해도 화면 기록 권한이 같은 앱으로 인식되게 한다.
codesign --force --sign - -r='designated => identifier "com.eddieee.Grabby"' "$app"

echo "$app"
