#!/usr/bin/env bash
# Creates dist/Afterglow-source-<version>-<date>.zip containing everything needed to open and
# build Afterglow in Xcode on a Mac, and nothing that is machine- or signing-specific.
# Usage: bash scripts/package-source.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

VERSION="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' ios/Afterglow.xcodeproj/project.pbxproj | head -n 1)"
STAMP="$(date -u +%Y%m%d)"
NAME="Afterglow-source-${VERSION:-dev}-${STAMP}"
OUT="$ROOT/dist/${NAME}.zip"
# mktemp gives a private directory that only this script created, so cleaning it is safe.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/afterglow-package.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT

mkdir -p "$ROOT/dist" "$STAGE/$NAME"
for path in ios docs scripts .github README.md LICENSE .gitignore .gitattributes; do
  if [ -e "$path" ]; then
    cp -R "$path" "$STAGE/$NAME/"
  fi
done

# Strip per-user Xcode state, build output and anything that could carry signing material.
find "$STAGE/$NAME" \( \
    -name xcuserdata -o -name DerivedData -o -name build -o -name dist -o -name .DS_Store -o \
    -name '*.mobileprovision' -o -name '*.provisionprofile' -o -name '*.p12' -o -name '*.cer' -o \
    -name '*.p8' -o -name '*.xcarchive' -o -name '*.ipa' -o -name '.env*' -o -name 'ExportOptions*.plist' \
  \) -prune -exec rm -rf -- {} +

# Normalise text files to LF so scripts run on macOS however they were checked out.
find "$STAGE/$NAME" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.swift' -o -name '*.yml' -o -name '*.md' \
    -o -name '*.plist' -o -name '*.pbxproj' -o -name '*.xcscheme' -o -name '*.xcprivacy' -o -name '*.json' \
    -o -name '*.xcworkspacedata' -o -name '*.ps1' -o -name '.gitattributes' -o -name '.gitignore' \) \
    -exec perl -pi -e 's/\r\n/\n/g' {} +

if grep -Eq 'DEVELOPMENT_TEAM = [A-Z0-9]{10};' "$STAGE/$NAME/ios/Afterglow.xcodeproj/project.pbxproj"; then
  echo "note: project.pbxproj contains a DEVELOPMENT_TEAM id; it is not secret, but the recipient must choose their own team." >&2
fi

rm -f -- "$OUT" "$OUT.sha256"
(cd "$STAGE" && zip -qr -X "$OUT" "$NAME")
(cd "$ROOT/dist" && shasum -a 256 "${NAME}.zip" | tee "${NAME}.zip.sha256")
echo "Wrote $OUT"
