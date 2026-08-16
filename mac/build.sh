#!/bin/bash
#
# Builds DangerousDave2.app — a self-contained macOS bundle wrapping index.html.
# Requires only the Xcode Command Line Tools (swiftc, iconutil, codesign).
#
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

APP_NAME="Dangerous Dave 2"
EXEC_NAME="DangerousDave2"
BUNDLE_ID="com.absrao.dangerousdave2"
VERSION="1.0"

APP="$ROOT/$EXEC_NAME.app"
CONTENTS="$APP/Contents"
BUILD="$ROOT/mac/.build"

echo "==> Cleaning"
rm -rf "$APP" "$BUILD"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$BUILD"

# The Command Line Tools can ship an SDK newer than their own swiftc (an SDK
# built by Swift 6.2 cannot be parsed by a 6.1 compiler). Probe for the newest
# SDK this compiler actually accepts instead of hardcoding a version.
echo "==> Selecting a compatible SDK"
SDK_FLAGS=()
probe() { swiftc -swift-version 5 "$@" -target arm64-apple-macos12.0 \
                 -o "$BUILD/probe" "$BUILD/probe.swift" 2>/dev/null; }
printf 'import Cocoa\nimport WebKit\nprint(WKWebView.self)\n' > "$BUILD/probe.swift"

if probe; then
  echo "    default SDK"
else
  FOUND=""
  for SDK in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -Vr); do
    if probe -sdk "$SDK"; then
      SDK_FLAGS=(-sdk "$SDK"); FOUND="$SDK"; break
    fi
  done
  if [ -z "$FOUND" ]; then
    echo "ERROR: no SDK on this machine is compatible with $(swiftc --version | head -1)" >&2
    echo "       Update the Command Line Tools: xcode-select --install" >&2
    exit 1
  fi
  echo "    $(basename "$FOUND")  (default SDK is too new for this swiftc)"
fi
rm -f "$BUILD/probe" "$BUILD/probe.swift"

echo "==> Generating app icon"
swiftc -O "${SDK_FLAGS[@]}" -o "$BUILD/makeicon" makeicon.swift
"$BUILD/makeicon" "$BUILD/$EXEC_NAME.iconset"
iconutil -c icns "$BUILD/$EXEC_NAME.iconset" -o "$CONTENTS/Resources/AppIcon.icns"

echo "==> Compiling Swift host (universal arm64 + x86_64)"
# Two slices so the bundle keeps working if it's ever copied to an Intel Mac.
swiftc -O -swift-version 5 "${SDK_FLAGS[@]}" \
       -target arm64-apple-macos12.0 \
       -o "$BUILD/$EXEC_NAME-arm64" main.swift
if swiftc -O -swift-version 5 "${SDK_FLAGS[@]}" \
          -target x86_64-apple-macos12.0 \
          -o "$BUILD/$EXEC_NAME-x86_64" main.swift 2>/dev/null; then
  lipo -create -output "$CONTENTS/MacOS/$EXEC_NAME" \
       "$BUILD/$EXEC_NAME-arm64" "$BUILD/$EXEC_NAME-x86_64"
  echo "    universal binary (arm64 + x86_64)"
else
  cp "$BUILD/$EXEC_NAME-arm64" "$CONTENTS/MacOS/$EXEC_NAME"
  echo "    arm64 only (x86_64 SDK slice unavailable)"
fi
chmod +x "$CONTENTS/MacOS/$EXEC_NAME"

echo "==> Bundling game"
cp "$ROOT/index.html" "$CONTENTS/Resources/index.html"

echo "==> Writing Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$EXEC_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>    <string>12.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.arcade-games</string>
    <key>NSHumanReadableCopyright</key>  <string>Personal build.</string>
</dict>
</plist>
PLIST
plutil -lint "$CONTENTS/Info.plist" > /dev/null

echo "==> Ad-hoc signing"
# Apple Silicon requires a valid signature; ad-hoc ("-") needs no developer account.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature OK"

echo "==> Refreshing Launch Services registration"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null || true

rm -rf "$BUILD"
echo ""
echo "Built: $APP"
du -sh "$APP" | awk '{print "Size:  " $1}'
