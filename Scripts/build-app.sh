#!/bin/bash
# SidecarPortrait.app(기본) 또는 UsageDashboard.app을 만든다.
#   Scripts/build-app.sh                           # build/SidecarPortrait.app 생성
#   Scripts/build-app.sh --install                 # ~/Applications에 복사까지
#   Scripts/build-app.sh UsageDashboard --install  # 사용량 대시보드 앱
#
# 서명: SIGN_IDENTITY 환경 변수 > 키체인의 첫 "Apple Development"/"Developer ID" 인증서 > ad-hoc.
# 인증서로 서명하면 다시 빌드해도 화면 녹음·손쉬운 사용 권한이 유지된다.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=SidecarPortrait
DISPLAY_NAME="Sidecar 세로"
if [ "${1:-}" = "UsageDashboard" ]; then
    NAME=UsageDashboard
    DISPLAY_NAME="AI 사용량"
    shift
fi
BUNDLE_ID=io.github.songyonggyu4006.$NAME
VERSION=$(git describe --tags --always 2>/dev/null || echo 0.1)
APP=build/$NAME.app

swift build -c release --arch arm64 --product "$NAME"
BIN=$(swift build -c release --arch arm64 --show-bin-path)/$NAME

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 대시보드의 백그라운드 수집기: 메뉴에서 켜면 SMAppService가 이 plist로 5분마다 --collect를 실행한다
if [ "$NAME" = "UsageDashboard" ]; then
    mkdir -p "$APP/Contents/Library/LaunchAgents"
    cat > "$APP/Contents/Library/LaunchAgents/$BUNDLE_ID.collector.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID.collector</string>
    <key>BundleProgram</key><string>Contents/MacOS/$NAME</string>
    <key>ProgramArguments</key>
    <array><string>Contents/MacOS/$NAME</string><string>--collect</string></array>
    <key>AssociatedBundleIdentifiers</key><string>$BUNDLE_ID</string>
    <key>StartInterval</key><integer>300</integer>
    <key>RunAtLoad</key><true/>
    <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLIST
fi

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E '"(Apple Development|Developer ID Application):' | head -1 | awk '{print $2}')}
if [ -z "$IDENTITY" ]; then
    IDENTITY=-
    echo "서명 인증서가 없어 ad-hoc으로 서명해요. 다시 빌드하면 권한을 다시 허용해야 할 수 있어요."
fi
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"
echo "만들었어요: $APP"

if [ "${1:-}" = "--install" ]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/$NAME.app
    cp -R "$APP" ~/Applications/
    echo "설치했어요: ~/Applications/$NAME.app"
fi
