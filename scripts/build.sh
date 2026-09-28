#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

if [[ "$(/usr/bin/uname -m)" != "arm64" ]]; then
  print -u2 "This build is for Apple silicon (arm64)."
  exit 1
fi

VERSION="$(<VERSION)"
PLIST="$PROJECT_DIR/GUI/Info.plist"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
[[ "$VERSION" == "$PLIST_VERSION" ]] || { print -u2 "VERSION and Info.plist disagree."; exit 1; }

OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
/bin/mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && /bin/pwd -P)"
FINAL_APP="$OUTPUT_DIR/$APP_NAME.app"
if [[ -e "$FINAL_APP" || -L "$FINAL_APP" ]]; then
  print -u2 "Refusing to overwrite: $FINAL_APP"
  print -u2 "Move the existing app yourself or choose another output directory."
  exit 1
fi

for tool in /usr/bin/xcrun /usr/bin/codesign /usr/bin/shasum; do
  [[ -x "$tool" ]] || { print -u2 "Required Apple build tool is missing: $tool"; exit 1; }
done

BUILD_DIR="$(/usr/bin/mktemp -d "$OUTPUT_DIR/.srttosound-build.XXXXXX")"
cleanup() {
  if [[ -n "${BUILD_DIR:-}" && -d "$BUILD_DIR" ]]; then
    /bin/rm -rf -- "$BUILD_DIR"
  fi
}
trap cleanup EXIT

APP="$BUILD_DIR/$APP_NAME.app"
RUNTIME="$APP/Contents/Resources/Runtime"
/bin/mkdir -p "$APP/Contents/MacOS" "$RUNTIME" "$BUILD_DIR/module-cache"

/usr/bin/xcrun swiftc "$PROJECT_DIR/GUI/main.swift" "$PROJECT_DIR/GUI/QueueSupport.swift" \
  -O -swift-version 5 -module-cache-path "$BUILD_DIR/module-cache" \
  -target arm64-apple-macosx15.0 -framework AppKit -framework AVFoundation -framework UserNotifications \
  -o "$APP/Contents/MacOS/SRTVoiceover"
/bin/cp "$PLIST" "$APP/Contents/Info.plist"
/bin/cp "$PROJECT_DIR/GUI/Assets/SRTVoiceover.icns" "$APP/Contents/Resources/SRTVoiceover.icns"

RUNTIME_FILES=(
  srt_gui_job.rb srt_voiceover.rb srt_output_policy.rb speech_normalizer.rb
  silero_worker.py requirements-silero.txt VERSION
)
for file in "${RUNTIME_FILES[@]}"; do
  [[ -f "$PROJECT_DIR/$file" ]] || { print -u2 "Required runtime file is missing: $file"; exit 1; }
  /bin/cp "$PROJECT_DIR/$file" "$RUNTIME/$file"
done

(
  cd "$PROJECT_DIR"
  /usr/bin/shasum -a 256 GUI/main.swift GUI/QueueSupport.swift GUI/Info.plist GUI/Assets/SRTVoiceover.icns \
    "${RUNTIME_FILES[@]}" > "$APP/Contents/Resources/build-sources.sha256"
)
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

if [[ -e "$FINAL_APP" || -L "$FINAL_APP" ]]; then
  print -u2 "Output appeared during the build; refusing to replace it: $FINAL_APP"
  exit 1
fi
/bin/mv "$APP" "$FINAL_APP"
print "Build ready: $FINAL_APP"
print "Not notarized. The build did not install or launch the app."
