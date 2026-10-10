#!/bin/bash
# DMG ke stažení (volá `make package`): MDView.app + odkaz na Aplikace, ikona svazku, podpis.
#   scripts/make-dmg.sh <MDView.app> <výstup.dmg>
# Bez Finderu a AppleScriptu – rozložení okna je výchozí (dvě ikony vedle sebe).
set -euo pipefail

APP=$1
OUT=$2
VOLUME=MDView
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mdview-dmg.XXXXXX")
MOUNT="$WORK/mount"
cleanup() {
    hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/src" "$MOUNT"
ditto "$APP" "$WORK/src/MDView.app"
ln -s /Applications "$WORK/src/Aplikace"
cp "$APP/Contents/Resources/AppIcon.icns" "$WORK/src/.VolumeIcon.icns"

# Zapisovatelný obraz → ikona svazku (atribut kořene) → komprimovaný obraz jen pro čtení.
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$WORK/src" -fs APFS -format UDRW -ov "$WORK/rw.dmg"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MOUNT" "$WORK/rw.dmg"
xcrun SetFile -a C "$MOUNT"
hdiutil detach -quiet "$MOUNT"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"

# Stejná identita jako aplikace (ad-hoc build se nepodepisuje).
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
if [ -n "$IDENTITY" ]; then
    codesign --sign "$IDENTITY" --timestamp=none "$OUT"
    codesign --verify "$OUT"
fi
hdiutil verify -quiet "$OUT"
