#!/bin/bash
# Aktualizuje vendorované web knihovny ve WebAssets podle web-vendor/package.json.
# npm běží v ~/Library/Caches (node_modules nesmí do iCloudu) a bez install skriptů.
# Po změně verzí: upravit package.json, spustit tento skript, zkontrolovat diff a commitnout
# i package-lock.json.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$HOME/Library/Caches/MDView/web-vendor"
DEST="$ROOT/Packages/MarkdownCore/Sources/WebAssets/Resources/web/vendor"

mkdir -p "$WORK"
cp "$ROOT/web-vendor/package.json" "$WORK/"
[ -f "$ROOT/web-vendor/package-lock.json" ] && cp "$ROOT/web-vendor/package-lock.json" "$WORK/"
(cd "$WORK" && npm install --ignore-scripts --no-audit --no-fund --save-exact >/dev/null)
cp "$WORK/package-lock.json" "$ROOT/web-vendor/package-lock.json"

M="$WORK/node_modules"
rm -rf "$DEST"
mkdir -p "$DEST"/{mermaid,katex/fonts,highlight.js,dompurify,github-markdown-css,octicons}

cp "$M/mermaid/dist/mermaid.min.js" "$M/mermaid/LICENSE" "$DEST/mermaid/"
cp "$M/katex/dist/katex.min.js" "$M/katex/dist/katex.min.css" "$M/katex/LICENSE" "$DEST/katex/"
cp "$M/katex/dist/fonts/"*.woff2 "$DEST/katex/fonts/"
cp "$M/katex/dist/contrib/copy-tex.min.js" "$DEST/katex/"
cp "$M/@highlightjs/cdn-assets/highlight.min.js" "$M/@highlightjs/cdn-assets/LICENSE" "$DEST/highlight.js/"
cp "$M/@highlightjs/cdn-assets/styles/github.min.css" "$M/@highlightjs/cdn-assets/styles/github-dark.min.css" "$DEST/highlight.js/"
cp "$M/dompurify/dist/purify.min.js" "$M/dompurify/LICENSE" "$DEST/dompurify/"
cp "$M/github-markdown-css/github-markdown.css" "$M/github-markdown-css/license" "$DEST/github-markdown-css/"
for icon in info light-bulb report alert stop; do
    cp "$M/@primer/octicons/build/svg/$icon-16.svg" "$DEST/octicons/"
done
cp "$M/@primer/octicons/LICENSE" "$DEST/octicons/"

# Emoji zkratky (:rocket:) pro renderer – mapování název → znak z gemoji (stejná data jako GitHub).
EMOJI="$ROOT/Packages/MarkdownCore/Sources/MarkdownCore/Resources"
mkdir -p "$EMOJI"
(cd "$WORK" && node --input-type=module -e '
import { gemoji } from "gemoji";
const map = {};
for (const entry of gemoji) for (const name of entry.names) map[name] = entry.emoji;
const sorted = Object.fromEntries(Object.keys(map).sort().map((key) => [key, map[key]]));
process.stdout.write(JSON.stringify(sorted, null, 0) + "\n");
') > "$EMOJI/emoji.json"
cp "$M/gemoji/license" "$EMOJI/gemoji-LICENSE"

(cd "$WORK" && node -e '
const lock = require("./package-lock.json").packages;
for (const [path, info] of Object.entries(lock)) {
  if (path.split("node_modules/").length === 2 && path) console.log(`${path.replace("node_modules/", "")}@${info.version}`);
}' | grep -E "^(@highlightjs/cdn-assets|@primer/octicons|dompurify|gemoji|github-markdown-css|katex|mermaid)@") > "$DEST/VERSIONS.txt"

echo "Vendor aktualizován:"
cat "$DEST/VERSIONS.txt"
du -sh "$DEST"
