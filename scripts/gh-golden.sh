#!/bin/bash
# Stáhne referenční výstupy GitHubu pro golden testy (Packages/MarkdownCore/Tests/.../Fixtures/golden):
#   *.github.html  – POST /markdown v režimu gfm (alerts, matika, task listy, Mermaid, footnotes)
#   *.slugs.txt    – kotvy nadpisů z režimu markdown (jako README na github.com)
# Spouštět po přidání nebo změně fixture; výsledky se commitují. Vyžaduje přihlášené `gh`.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)/Packages/MarkdownCore/Tests/MarkdownCoreTests/Fixtures/golden"
ONLY=${1:-}

for fixture in "$DIR"/*.md; do
    name=$(basename "$fixture" .md)
    [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && continue
    gh api markdown -f mode=gfm -F text=@"$fixture" > "$DIR/$name.github.html"
    gh api markdown -f mode=markdown -F text=@"$fixture" \
        | grep -o 'id="user-content-[^"]*" class="anchor"' \
        | sed -E 's/id="user-content-([^"]*)" class="anchor"/\1/' > "$DIR/$name.slugs.txt" || true
    [ -s "$DIR/$name.slugs.txt" ] || rm -f "$DIR/$name.slugs.txt"
    echo "✓ $name"
done
