#!/usr/bin/env bash
# Builds Afterglow for a generic iOS device (unsigned) and runs the unit tests on the newest
# available iPhone simulator. Used by .github/workflows/ios.yml and runnable locally on a Mac:
#   ./scripts/ci-test.sh
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="ios/Afterglow.xcodeproj"
SCHEME="Afterglow"
DERIVED_DATA="build/DerivedData"
# A fresh, uniquely named result bundle per run, so nothing ever has to be deleted.
mkdir -p build
RESULTS="build/TestResults-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult"

xcodebuild -version
XCODE_MAJOR="$(xcodebuild -version | awk 'NR==1 { split($2, v, "."); print v[1] }')"
if [ "${XCODE_MAJOR:-0}" -lt 16 ]; then
  echo "error: Xcode 16 or newer is required (the project uses synchronized folders)." >&2
  exit 1
fi

if [ -z "${SIMULATOR_ID:-}" ]; then
  SIMULATOR_ID="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.rsplit("iOS-", 1)[1].split("-") if part.isdigit())
    if version < (17,):
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            if best is None or version > best[0]:
                best = (version, device["udid"], device["name"])
if best:
    print(best[1])
')"
fi

if [ -z "$SIMULATOR_ID" ]; then
  echo "error: no available iPhone simulator with iOS 17+ was found." >&2
  xcrun simctl list devices available >&2
  exit 1
fi
echo "Using simulator $SIMULATOR_ID"

echo "::group::Build for generic iOS device (unsigned)"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
echo "::endgroup::"

echo "::group::Unit tests on simulator"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULTS" \
  CODE_SIGNING_ALLOWED=NO
echo "::endgroup::"
