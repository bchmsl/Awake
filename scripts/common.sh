# Shared settings for build-app.sh and test.sh. Sourced, not executed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Build output lives outside iCloud Drive: iCloud adds extended attributes that
# break codesign, syncs thousands of build files, and can evict them.
BUILD_DIR="${AWAKE_BUILD_DIR:-$HOME/Library/Caches/Awake-build}"
SCRATCH_PATH="$BUILD_DIR/spm"

# Workaround for a broken Command Line Tools install.
#
# Some installs keep stale Swift 5.10 `*.private.swiftinterface` files next to
# SwiftPM's current PackageDescription module. The compiler prefers them over the
# current interface, so every Package.swift fails to link ("Undefined symbols ...
# Package.__allocating_init"). When both files exist, point SwiftPM at a clean
# copy of its libraries without the private interfaces. Nothing in the toolchain
# is modified.
prepare_swiftpm() {
    local pm_dir
    pm_dir="$(cd "$(dirname "$(xcrun --find swift)")/../lib/swift/pm" && pwd)"
    local module="$pm_dir/ManifestAPI/PackageDescription.swiftmodule"

    if compgen -G "$module/*.private.swiftinterface" >/dev/null &&
        compgen -G "$module/*-apple-macos.swiftinterface" >/dev/null; then
        local clean="$BUILD_DIR/pm-libs"
        rm -rf "$clean"
        mkdir -p "$clean"
        rsync -a --exclude '*.private.swiftinterface' "$pm_dir/ManifestAPI" "$pm_dir/PluginAPI" "$clean/"
        export SWIFTPM_CUSTOM_LIBS_DIR="$clean"
    fi
}
