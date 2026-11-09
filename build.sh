#!/bin/zsh
# Builds "Disk Temizle.app" into ./build
set -e
cd "$(dirname "$0")"
APP="build/Disk Temizle.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos14 Sources/main.swift -o "$APP/Contents/MacOS/DiskTemizle"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "OK: $APP"
