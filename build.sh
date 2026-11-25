#!/bin/zsh
# ./build.sh            -> build/Vitals.app (this Mac's architecture)
# ./build.sh install    -> additionally copy to /Applications and launch
#
# Signing: ad-hoc by default. Set SIGN_IDENTITY to a certificate name to sign with it instead.
set -e
cd "$(dirname "$0")"

MODE=${1:-build}
VERSION=${2:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)}
APP=build/Vitals.app

if [[ ! -f Resources/AppIcon.icns || scripts/make_icon.swift -nt Resources/AppIcon.icns ]]; then
    ICONSET=build/AppIcon.iconset
    mkdir -p $ICONSET
    swift scripts/make_icon.swift build/icon_1024.png
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon_1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
        sips -z $((s*2)) $((s*2)) build/icon_1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
    done
    iconutil -c icns $ICONSET -o Resources/AppIcon.icns
fi

swift build -c release
BIN=$(swift build -c release --show-bin-path)/Vitals

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BIN $APP/Contents/MacOS/Vitals
cp Resources/Info.plist $APP/Contents/
cp Resources/AppIcon.icns $APP/Contents/Resources/
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" $APP/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $VERSION" $APP/Contents/Info.plist

codesign --force --sign "${SIGN_IDENTITY:--}" $APP
echo "Gebaut: $APP ($VERSION)"

if [[ $MODE == install ]]; then
    pkill -x Vitals || true
    rm -rf /Applications/Vitals.app
    cp -R $APP /Applications/
    open /Applications/Vitals.app
    echo "Installiert und gestartet: /Applications/Vitals.app"
fi
