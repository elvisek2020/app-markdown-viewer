#!/bin/bash
# Vydání na GitHub Releases (volá `make publish` po `make package`):
#   scripts/publish.sh <verze> <cesta k MDView.zip>
# Tag v<verze> vznikne na aktuálním commitu, který musí být čistý a pushnutý do origin/main.
set -euo pipefail

VERSION=$1
ZIP=$2
REPO=elvisek2020/app-markdown-viewer

git diff --quiet HEAD || { echo "Necommitnuté změny – nejdřív commit." >&2; exit 1; }
git fetch -q origin main
HEAD=$(git rev-parse HEAD)
[ "$HEAD" = "$(git rev-parse origin/main)" ] || { echo "HEAD není totožný s origin/main – nejdřív push." >&2; exit 1; }

PREVIOUS=$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null || true)
NOTES=$(mktemp)
trap 'rm -f "$NOTES"' EXIT
{
    echo "Instalace bez buildu (Apple Silicon, macOS 15+):"
    echo
    echo '```bash'
    echo "curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
    echo '```'
    echo
    echo "Ručně: stáhni \`MDView.zip\`, rozbal a přesuň \`MDView.app\` do Aplikací. Aplikace není notarizovaná –"
    echo "při prvním spuštění ji povol v Nastavení systému → Soukromí a zabezpečení → Přesto otevřít."
    if [ -n "$PREVIOUS" ]; then
        echo
        echo "Změny: https://github.com/$REPO/compare/$PREVIOUS...v$VERSION"
    fi
} > "$NOTES"

gh release create "v$VERSION" "$ZIP" --repo "$REPO" --target "$HEAD" \
    --title "MDView $VERSION" --notes-file "$NOTES"
echo "Vydáno: https://github.com/$REPO/releases/tag/v$VERSION"
