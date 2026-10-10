#!/bin/bash
# Instalace MDView bez buildu – stáhne poslední vydání z GitHub Releases:
#
#   curl -fsSL https://raw.githubusercontent.com/elvisek2020/app-markdown-viewer/main/install.sh | bash
#
# Aplikace jde do /Applications, CLI `mdv` do /opt/homebrew/bin (nebo /usr/local/bin) a Quick Look
# rozšíření se zaregistruje. Konkrétní verze: MDV_VERSION=20261010.1754 (jinak poslední).
set -euo pipefail

REPO=elvisek2020/app-markdown-viewer
APP_DIR=/Applications
APP="$APP_DIR/MDView.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ -n "${MDV_VERSION:-}" ]; then
    URL="https://github.com/$REPO/releases/download/v$MDV_VERSION/MDView.zip"
else
    URL="https://github.com/$REPO/releases/latest/download/MDView.zip"
fi

[ "$(uname -m)" = "arm64" ] || { echo "MDView je jen pro Apple Silicon." >&2; exit 1; }
MACOS=$(sw_vers -productVersion)
[ "${MACOS%%.*}" -ge 15 ] || { echo "MDView potřebuje macOS 15 nebo novější (tady je $MACOS)." >&2; exit 1; }

if [ -d "$APP" ]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null | grep -qx cz.elvisek.mdview \
        || { echo "$APP není MDView od cz.elvisek – nepřepisuji." >&2; exit 1; }
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
echo "Stahuji $URL"
curl -fL --progress-bar -o "$WORK/MDView.zip" "$URL"
ditto -x -k "$WORK/MDView.zip" "$WORK"
[ -d "$WORK/MDView.app" ] || { echo "Balíček neobsahuje MDView.app." >&2; exit 1; }
codesign --verify --deep --strict "$WORK/MDView.app" || { echo "Podpis aplikace nesedí – neinstaluji." >&2; exit 1; }

rm -rf "$APP"
ditto "$WORK/MDView.app" "$APP"
# Aplikace není notarizovaná. Stažení přes curl karanténu nenastavuje; kdyby ji něco přidalo,
# Gatekeeper by spuštění zablokoval.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
touch "$APP"

"$LSREGISTER" -f "$APP"
pluginkit -a "$APP/Contents/PlugIns/MDViewQuickLook.appex" 2>/dev/null || true
pluginkit -e use -i cz.elvisek.mdview.quicklook 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true

BIN=""
for dir in /opt/homebrew/bin /usr/local/bin; do
    if [ -d "$dir" ] && [ -w "$dir" ]; then
        ln -sf "$APP/Contents/Resources/bin/mdv" "$dir/mdv"
        BIN="$dir/mdv"
        break
    fi
done

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
echo "Nainstalováno: $APP (verze $VERSION)"
if [ -n "$BIN" ]; then
    echo "CLI: $BIN"
else
    echo "CLI: nenašel jsem zapisovatelný adresář v PATH, nalinkuj ho ručně:"
    echo "  sudo ln -sf \"$APP/Contents/Resources/bin/mdv\" /usr/local/bin/mdv"
fi
if pgrep -qf "^$APP/Contents/MacOS/MDView"; then
    echo "MDView běží ze staré verze – ukonči ho (⌘Q) a spusť znovu."
fi
