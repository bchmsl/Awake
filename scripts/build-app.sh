#!/usr/bin/env bash
# Builds, assembles, and signs Awake.app outside iCloud Drive.
#
# Usage:
#   scripts/build-app.sh             Build and sign the app into the build folder.
#   scripts/build-app.sh --install   Also stop a running Awake, copy the app to
#                                    ~/Applications, and launch it.
#
# Environment:
#   AWAKE_BUILD_DIR        Build folder. Default: ~/Library/Caches/Awake-build
#   AWAKE_SIGN_IDENTITY    Code signing identity. Default: "-" (ad-hoc)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

APP="$BUILD_DIR/Awake.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/Awake.app"
SIGN_IDENTITY="${AWAKE_SIGN_IDENTITY:--}"

install=false
case "${1:-}" in
    "") ;;
    --install) install=true ;;
    -h | --help)
        sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 64
        ;;
esac

prepare_swiftpm

MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw "$ROOT/Support/Info.plist")"
SDK_VERSION="$(xcrun --show-sdk-version)"
# With the Command Line Tools, SwiftPM's default backend (Swift Build) records the
# deployment target as the binary's SDK version. AppKit uses the recorded SDK to pick
# appearance and compatibility behavior, so pass the real values to the linker.
LINK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION")

echo "==> Building (release, macOS $MIN_MACOS+, SDK $SDK_VERSION)"
swift build -c release "${LINK_FLAGS[@]}" --package-path "$ROOT" --scratch-path "$SCRATCH_PATH"
BIN_DIR="$(swift build -c release "${LINK_FLAGS[@]}" --package-path "$ROOT" --scratch-path "$SCRATCH_PATH" --show-bin-path)"

RECORDED_SDK="$(vtool -show-build "$BIN_DIR/Awake" | awk '$1 == "sdk" { print $2 }')"
if [[ "$RECORDED_SDK" != "$SDK_VERSION" ]]; then
    echo "error: binary records SDK $RECORDED_SDK, expected $SDK_VERSION" >&2
    exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Awake" "$APP/Contents/MacOS/Awake"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Support/AppIcon.icns" ]]; then
    cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
plutil -lint "$APP/Contents/Info.plist"

echo "==> Signing (identity: $SIGN_IDENTITY)"
# Extended attributes (for example from iCloud) make codesign fail.
xattr -cr "$APP"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ "$install" == true ]]; then
    if pgrep -x Awake >/dev/null; then
        echo "==> Stopping running Awake"
        # SIGTERM is safe: the app never writes state on termination, and
        # powerd releases the assertion when the process exits.
        pkill -x Awake || true
        for _ in {1..50}; do
            pgrep -x Awake >/dev/null || break
            sleep 0.1
        done
    fi

    echo "==> Installing to $INSTALLED_APP"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALLED_APP"
    ditto "$APP" "$INSTALLED_APP"
    open "$INSTALLED_APP"
    echo "==> Done: $INSTALLED_APP"
else
    echo "==> Done: $APP"
fi
