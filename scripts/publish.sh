#!/bin/bash
# Vydání na GitHub Releases (volá `make publish` po `make package`):
#   scripts/publish.sh <verze> <MDView.dmg> <MDView.zip>
#   scripts/publish.sh --notes <verze>        jen vypíše text vydání
# Tag v<verze> vznikne na aktuálním commitu, který musí být čistý a pushnutý do origin/main.
set -euo pipefail

REPO=elvisek2020/app-markdown-viewer

notes() {
    local version=$1 previous
    previous=$(gh release list --repo "$REPO" --json tagName --jq "[.[] | select(.tagName != \"v$version\")][0].tagName // empty" 2>/dev/null || true)
    cat <<EOF
Pro Apple Silicon a macOS 15+.

**Stažení:** otevři \`MDView.dmg\` a přetáhni MDView do složky Aplikace.

Aplikace je podepsaná, ale není notarizovaná. Při prvním spuštění macOS ohlásí, že ji nemůže ověřit. Otevři Nastavení systému → Soukromí a zabezpečení a klikni na **Přesto otevřít**. Totéž zařídí v Terminálu \`xattr -dr com.apple.quarantine /Applications/MDView.app\`.

Příkaz \`mdv\` pro terminál: \`ln -sf /Applications/MDView.app/Contents/Resources/bin/mdv /opt/homebrew/bin/mdv\`

**Instalace z Terminálu** (včetně \`mdv\` a Quick Look, stejným příkazem i aktualizace):

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash
\`\`\`
EOF
    if [ -n "$previous" ]; then
        printf '\nZměny: https://github.com/%s/compare/%s...v%s\n' "$REPO" "$previous" "$version"
    fi
}

if [ "${1:-}" = "--notes" ]; then
    notes "$2"
    exit 0
fi

VERSION=$1
shift

git diff --quiet HEAD || { echo "Necommitnuté změny – nejdřív commit." >&2; exit 1; }
git fetch -q origin main
HEAD=$(git rev-parse HEAD)
[ "$HEAD" = "$(git rev-parse origin/main)" ] || { echo "HEAD není totožný s origin/main – nejdřív push." >&2; exit 1; }

NOTES=$(mktemp)
trap 'rm -f "$NOTES"' EXIT
notes "$VERSION" > "$NOTES"
gh release create "v$VERSION" "$@" --repo "$REPO" --target "$HEAD" \
    --title "MDView $VERSION" --notes-file "$NOTES"
echo "Vydáno: https://github.com/$REPO/releases/tag/v$VERSION"
