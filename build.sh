#!/bin/sh
set -eu

cd "$(dirname "$0")"
port_dir=$(pwd -P)
bundle="$port_dir/dist/MP3 Strip Rebuild.app"
mkdir -p "$port_dir/.build/tmp" "$bundle/Contents/MacOS"
export TMPDIR="$port_dir/.build/tmp"
export XCRUN_CACHE_DISABLE=1

arch=$(uname -m)
swiftc -swift-version 5 -O -target "${arch}-apple-macos13.0" \
    -module-cache-path "$port_dir/.build/modules" \
    "$port_dir/Library.swift" "$port_dir/App.swift" \
    -o "$port_dir/.build/MP3StripRebuild"
cp "$port_dir/Info.plist" "$bundle/Contents/Info.plist"
mv "$port_dir/.build/MP3StripRebuild" "$bundle/Contents/MacOS/MP3StripRebuild"
/usr/bin/codesign --force --sign - --timestamp=none "$bundle"
printf '%s\n' "$bundle"
