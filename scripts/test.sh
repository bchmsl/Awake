#!/usr/bin/env bash
# Runs the test suite with the build output outside iCloud Drive.
# Extra arguments are passed to `swift test`, for example: scripts/test.sh --filter PowerAssertion
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
prepare_swiftpm

# Workaround: with the Command Line Tools, SwiftPM's Swift Build backend sometimes
# does not give the compiler the Swift Testing macro plugin, and the build fails with
# "plugin for module 'TestingMacros' not found". Pass the toolchain's plugin folder.
TESTING_PLUGINS="$(cd "$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins" && pwd)/testing"
PLUGIN_FLAGS=()
if [[ -d "$TESTING_PLUGINS" ]]; then
    PLUGIN_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS")
fi

# The ${a[@]+...} form keeps an empty array safe under `set -u` in macOS bash 3.2.
swift test --package-path "$ROOT" --scratch-path "$SCRATCH_PATH" ${PLUGIN_FLAGS[@]+"${PLUGIN_FLAGS[@]}"} "$@"
