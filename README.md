# MDView

Nativní Markdown viewer pro macOS (Apple Silicon) na sledování `.md` souborů, které zapisuje AI agent nebo editor.

- **Spolehlivý auto-reload**: přežije atomic save, rychlé série zápisů, smazání a znovuvytvoření i přejmenování. Reload probíhá potichu a zachová pozici scrollu.
- **Rendering věrný GitHubu**: cmark-gfm (GFM, footnotes) + GitHub alerts, Mermaid, matika (KaTeX) a front matter.
- **Bezpečný**: JS z dokumentu nikdy neběží a odkazy nic nespouštějí.
- **Offline**: všechny knihovny jsou vendorované.
- CLI `mdv`, zdrojový panel se scroll sync, TOC, hledání, export a Quick Look.

Stav: fáze F0 (jádro a spiky), viz [docs/PLAN.md](docs/PLAN.md).

## Vývoj

```bash
cd Packages/MarkdownCore && swift test
```

Požadavky: macOS 15+, Apple Silicon, Xcode 26+.
