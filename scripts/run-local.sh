#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if pgrep -x PerformanceDaddy >/dev/null; then
    echo "Quit PerformanceDaddy before rebuilding the local app."
    exit 1
fi
swift build --product PerformanceDaddy
bin_path="$(swift build --show-bin-path)"
python3 -c 'import sys; sys.path.insert(0, "scripts"); import package_resources; from pathlib import Path; package_resources.resource_bundles(Path(sys.argv[1]))' "$bin_path"
bundle_path="$PWD/.build/PerformanceDaddy.app"
framework_path="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
test -d "$framework_path"
mkdir -p "$bundle_path/Contents/MacOS" "$bundle_path/Contents/Resources" "$bundle_path/Contents/Frameworks"
if [ ! -d "$bundle_path/Contents/Frameworks/Sparkle.framework" ]; then
    cp -R "$framework_path" "$bundle_path/Contents/Frameworks/"
fi
# Replace the inode, never rewrite executable pages in place.
cp "$bin_path/PerformanceDaddy" "$bundle_path/Contents/MacOS/PerformanceDaddy.next"
mv -f "$bundle_path/Contents/MacOS/PerformanceDaddy.next" "$bundle_path/Contents/MacOS/PerformanceDaddy"
cp Support/Info.plist "$bundle_path/Contents/Info.plist"
cp Support/PerformanceDaddy.icns "$bundle_path/Contents/Resources/PerformanceDaddy.icns"
python3 scripts/package_resources.py --products "$bin_path" --destination "$bundle_path/Contents/Resources"
open "$bundle_path"
