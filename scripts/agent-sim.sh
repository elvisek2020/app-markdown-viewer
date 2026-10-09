#!/bin/bash
# Simuluje, jak AI agent a editory zapisují .md soubor – pro ruční i stresové
# testování auto-reloadu v MDView. Náhled musí vždy skončit na posledním obsahu
# („Revize N“), bez dialogu a bez bliknutí prázdného dokumentu.
#
# Použití: scripts/agent-sim.sh <soubor.md> [scénář|all] [počet opakování]
# Scénáře: atomic append truncate recreate mvaway vim gitcheckout burst

set -euo pipefail

FILE=${1:?Použití: $0 <soubor.md> [scénář|all] [počet]}
SCENARIO=${2:-all}
REPEAT=${3:-1}
DIR=$(cd "$(dirname "$FILE")" && pwd)
NAME=$(basename "$FILE")
TARGET="$DIR/$NAME"
REVISION=0

# Dokument s počítadlem revizí, nadpisy a delším obsahem (kvůli scrollu).
content() {
    REVISION=$((REVISION + 1))
    cat <<EOF
# Simulace agenta – revize $REVISION

Scénář: **$1**, čas: $(date +%H:%M:%S)

> [!NOTE]
> Náhled musí ukazovat poslední revizi bez dialogu a beze ztráty scrollu.

## Tabulka

| Revize | Scénář |
|---|---|
| $REVISION | $1 |

## Dlouhý obsah

$(for i in $(seq 1 40); do echo "Odstavec $i revize $REVISION. Lorem ipsum dolor sit amet, consectetur adipiscing elit."; echo; done)

## Konec

Revize $REVISION
EOF
}

atomic() {
    # Zápis do dočasného souboru a rename přes původní (Foundation, většina editorů, agenti).
    for _ in $(seq 1 20); do
        content atomic > "$TARGET.tmp.$$"
        mv -f "$TARGET.tmp.$$" "$TARGET"
        sleep 0.05
    done
}

append() {
    # Agent streamuje výstup: 200 B každých 20 ms.
    content append > "$TARGET.src.$$"
    : > "$TARGET"
    local size offset=0
    size=$(wc -c < "$TARGET.src.$$")
    while [ "$offset" -lt "$size" ]; do
        dd if="$TARGET.src.$$" bs=1 skip="$offset" count=200 status=none >> "$TARGET"
        offset=$((offset + 200))
        sleep 0.02
    done
    rm -f "$TARGET.src.$$"
}

truncate_write() {
    # Zkrácení na nulu a zápis (shell redirect, některé nástroje).
    content truncate > "$TARGET.src.$$"
    : > "$TARGET"
    sleep 0.05
    cat "$TARGET.src.$$" > "$TARGET"
    rm -f "$TARGET.src.$$"
}

recreate() {
    # Smazání a znovuvytvoření po 5 s – náhled má ukázat banner a pak se vzpamatovat.
    rm -f "$TARGET"
    sleep 5
    content recreate > "$TARGET"
}

mvaway() {
    # Přesun pryč a zpět (git stash, refaktoring).
    mv "$TARGET" "$TARGET.away"
    sleep 2
    mv "$TARGET.away" "$TARGET"
    content mvaway > "$TARGET"
}

vim_save() {
    # Vim s backupcopy=no: přejmenovat původní na záložní, zapsat nový, záložní smazat.
    mv "$TARGET" "$TARGET~"
    content vim > "$TARGET"
    rm -f "$TARGET~"
}

gitcheckout() {
    # git checkout přepíše soubor (unlink + create) spolu s dalšími soubory v adresáři.
    content gitcheckout > "$DIR/.$NAME.gitnew"
    rm -f "$TARGET"
    mv "$DIR/.$NAME.gitnew" "$TARGET"
    touch "$DIR/.agent-sim-sibling" && rm -f "$DIR/.agent-sim-sibling"
}

burst() {
    # 500 atomických zápisů co nejrychleji.
    for _ in $(seq 1 500); do
        content burst > "$TARGET.tmp.$$"
        mv -f "$TARGET.tmp.$$" "$TARGET"
    done
}

run() {
    local scenario=$1
    local started
    started=$(date +%s)
    case "$scenario" in
        atomic) atomic ;;
        append) append ;;
        truncate) truncate_write ;;
        recreate) recreate ;;
        mvaway) mvaway ;;
        vim) vim_save ;;
        gitcheckout) gitcheckout ;;
        burst) burst ;;
        *) echo "Neznámý scénář: $scenario" >&2; exit 1 ;;
    esac
    echo "✓ $scenario – poslední revize $REVISION ($(($(date +%s) - started)) s)"
    sleep 1
}

[ -f "$TARGET" ] || content init > "$TARGET"

for _ in $(seq 1 "$REPEAT"); do
    if [ "$SCENARIO" = all ]; then
        for scenario in atomic append truncate recreate mvaway vim gitcheckout burst; do
            run "$scenario"
        done
    else
        run "$SCENARIO"
    fi
done

echo "Hotovo. Náhled musí ukazovat „Revize ${REVISION}“."
