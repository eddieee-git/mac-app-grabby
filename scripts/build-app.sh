#!/bin/zsh
# build/Grabby.app과 배포용 build/Grabby.dmg를 만든다. Xcode 없이 Command Line Tools만으로 빌드한다.
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

# scripts/make-signing-cert.sh로 만든 인증서가 있으면 그것으로 서명한다. 다시 빌드해도 화면 기록 권한이 유지된다.
# 없으면 임시 서명을 하되, 서명 조건을 번들 ID로 지정해서 같은 앱으로 인식되게 한다.
identity="Grabby Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$identity" \
   || security find-certificate -c "$identity" >/dev/null 2>&1; then
    codesign --force --sign "$identity" "$app"
else
    codesign --force --sign - -r='designated => identifier "com.eddieee.Grabby"' "$app"
fi

# 내려받은 쪽에서 응용 프로그램 폴더로 끌어다 놓을 수 있게 바로가기를 함께 넣는다.
staging=build/dmg
rm -rf "$staging" build/Grabby.dmg
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Grabby -srcfolder "$staging" -format UDZO build/Grabby.dmg
rm -rf "$staging"

echo "$app"
echo build/Grabby.dmg
