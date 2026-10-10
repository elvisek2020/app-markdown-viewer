#!/bin/bash
# DMG ke stažení (volá `make package`): MDView.app a odkaz na Aplikace na pozadí se šipkou.
#   scripts/make-dmg.sh <MDView.app> <výstup.dmg>
#
# Rozložení okna (.DS_Store s pozadím a pozicemi ikon) zapisuje dmgbuild bez Finderu a AppleScriptu;
# instaluje se jednou do venv v build cache. Pozadí kreslí scripts/dmg-background.swift (1× a 2×).
#
# DMG se záměrně nepodepisuje: podepsané, ale nenotarizované DMG Gatekeeper po stažení z internetu
# odmítne otevřít („Soubor MDView.dmg nebyl otevřen“). Nepodepsané se otevře a kontrolou jednou
# projde až aplikace (Nastavení systému → Soukromí a zabezpečení → Přesto otevřít).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=$1
OUT=$2
VENV="$HOME/Library/Caches/MDView/dmgbuild-venv"
DMGBUILD_VERSION=1.6.5

if [ "$("$VENV/bin/pip" show dmgbuild 2>/dev/null | sed -n 's/^Version: //p')" != "$DMGBUILD_VERSION" ]; then
    echo "Instaluji dmgbuild $DMGBUILD_VERSION do $VENV"
    /usr/bin/python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q --disable-pip-version-check "dmgbuild==$DMGBUILD_VERSION"
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mdview-dmg.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
swift "$ROOT/scripts/dmg-background.swift" "$WORK/background.png" 1
swift "$ROOT/scripts/dmg-background.swift" "$WORK/background@2x.png" 2
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" 2>/dev/null

rm -f "$OUT"
# dmgbuild volá hdiutil, který vypisuje upozornění na zastaralé volby – výstup jen při chybě.
if ! "$VENV/bin/dmgbuild" -s "$ROOT/scripts/dmg-settings.py" \
    -D app="$APP" -D background="$WORK/background.tiff" MDView "$OUT" > "$WORK/dmgbuild.log" 2>&1; then
    cat "$WORK/dmgbuild.log" >&2
    exit 1
fi
hdiutil verify -quiet "$OUT"

# Aplikace v obrazu musí projít přísným ověřením podpisu (žádné atributy Finderu navíc).
MOUNT="$WORK/mount"
mkdir -p "$MOUNT"
hdiutil attach -quiet -nobrowse -noautoopen -readonly -mountpoint "$MOUNT" "$OUT"
STATUS=0
codesign --verify --deep --strict "$MOUNT/MDView.app" || STATUS=$?
hdiutil detach -quiet "$MOUNT"
[ "$STATUS" -eq 0 ] || { echo "Aplikace v DMG neprošla ověřením podpisu." >&2; exit 1; }
