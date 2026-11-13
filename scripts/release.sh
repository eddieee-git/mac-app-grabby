#!/bin/zsh
# GitHub 릴리스를 만든다: 점검 → 빌드(dmg) → 태그 → 릴리스에 dmg 첨부.
# 버전은 Resources/Info.plist의 CFBundleShortVersionString을 쓴다. 릴리스 노트는 docs/releases/v<버전>.md.
# 사용: ./scripts/release.sh
set -e
cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
tag="v$version"
notes="docs/releases/$tag.md"

if [[ ! -f "$notes" ]]; then
    echo "릴리스 노트가 없어요: $notes"
    exit 1
fi
if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "이미 있는 태그예요: $tag (Info.plist의 버전을 올려 주세요)"
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "커밋하지 않은 변경이 있어요. 먼저 커밋해 주세요."
    exit 1
fi

./scripts/test.sh
./scripts/build-app.sh
if [[ ! -f "build/Grabby-$version.dmg.sig" ]]; then
    echo "업데이트 서명(.sig)이 없어요. ~/.config/grabby/update-signing.key를 확인해 주세요."
    exit 1
fi

git tag -a "$tag" -m "Grabby $version"
git push origin "$tag"
gh release create "$tag" "build/Grabby-$version.dmg" "build/Grabby-$version.dmg.sig" --title "Grabby $version" --notes-file "$notes"
echo "릴리스를 만들었어요: $tag"
