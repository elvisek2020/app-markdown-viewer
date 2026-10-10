// MDView – logika náhledu.
//
// Běží jako WKUserScript v izolovaném WKContentWorld „mdview“. JavaScript stránky
// (tj. cokoli z Markdown dokumentu) je vypnutý přes allowsContentJavaScript = false,
// DOM je sdílený, globální proměnné ne. Knihovny (DOMPurify, highlight.js, KaTeX,
// Mermaid) vkládá Swift do stejného worldu, ty větší líně podle obsahu dokumentu.
//
// Swift volá: mdv.update(payload), setStatus, scrollToLine, setFollowTail, setSource, find, findStep,
//             selectionText, exportContent, flushDiagrams
// Swift dostává: { type: "ready" | "link" | "scroll" | "sourceWidth" | "error", … } přes webkit.messageHandlers.mdv

(() => {
  "use strict";

  const post = (message) => {
    try {
      webkit.messageHandlers.mdv.postMessage(message);
    } catch (error) {
      // Handler chybí jen mimo aplikaci (např. při ladění v prohlížeči).
    }
  };

  const scroller = () => document.getElementById("mdv-scroll");
  const content = () => document.getElementById("mdv-content");

  const state = {
    generation: 0,
    hasContent: false,
    followTail: true,
    remoteImages: true,
    hold: null,
    mermaidCounter: 0,
  };

  // MARK: - Pomocné funkce

  /** FNV-1a 32 bit + délka – klíč bloku pro reconciliation. */
  function hash(text) {
    let value = 0x811c9dc5;
    for (let index = 0; index < text.length; index++) {
      value ^= text.charCodeAt(index);
      value = Math.imul(value, 0x01000193);
    }
    return (value >>> 0).toString(36) + "-" + text.length.toString(36);
  }

  const withoutSourcepos = (html) => html.replace(/ data-sourcepos="[^"]*"/g, "");

  function startLine(element) {
    const value = element.getAttribute("data-sourcepos");
    return value ? parseInt(value, 10) : NaN;
  }

  /** Prvky odpovídající selektoru včetně samotného kořene. */
  function withSelf(root, selector) {
    const found = [...root.querySelectorAll(selector)];
    return root.matches?.(selector) ? [root, ...found] : found;
  }

  function elementTop(element) {
    const container = scroller();
    return element.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop;
  }

  const prefersDark = () => window.matchMedia("(prefers-color-scheme: dark)").matches;

  // MARK: - Sanitizace a URL

  const purifyConfig = {
    FORBID_TAGS: [
      "style", "form", "button", "textarea", "select", "option", "iframe", "frame", "frameset",
      "object", "embed", "link", "meta", "base", "dialog", "template", "slot",
    ],
    FORBID_ATTR: ["style", "target", "formaction"],
    ALLOW_DATA_ATTR: true,
    // Odkazy smí mít jakékoli schéma kromě skriptovacích – o otevření rozhoduje Swift (allowlist).
    ALLOWED_URI_REGEXP: /^(?!\s*(?:javascript|vbscript|data):)/i,
    RETURN_DOM_FRAGMENT: true,
  };

  let purifyReady = false;

  function setupPurify() {
    if (purifyReady) return;
    purifyReady = true;
    DOMPurify.addHook("uponSanitizeElement", (node, data) => {
      // Z formulářových prvků zůstávají jen checkboxy task listů.
      if (data.tagName === "input" && node.getAttribute?.("type") !== "checkbox") {
        node.parentNode?.removeChild(node);
      }
    });
    DOMPurify.addHook("afterSanitizeAttributes", (node) => {
      if (node.tagName === "INPUT") node.setAttribute("disabled", "");
    });
  }

  /**
   * URL z dokumentu → URL pro náhled: relativní vůči adresáři dokumentu jako `mdv-file://`
   * (bez `<base>`, kvůli #kotvám). `null` = atribut odstranit.
   */
  function resolveURL(value, baseURL, isLink) {
    if (value.startsWith("#")) return value;
    if (value.startsWith("//")) return "https:" + value;
    // Obrázky z file: URL načte jen náš handler; odkazy na file: řeší Swift (Reveal in Finder).
    if (/^file:/i.test(value)) return isLink ? value : value.replace(/^file:/i, "mdv-file:");
    if (/^[a-z][a-z0-9+.-]*:/i.test(value)) return value;
    try {
      return new URL(value, baseURL).href;
    } catch (error) {
      return null;
    }
  }

  /** Vzdálené obrázky vypnuté v nastavení: http(s) zdroj se neodešle, zůstane jen alt. */
  function blockRemoteImages(root) {
    for (const element of root.querySelectorAll("img[src], source[srcset], video[src], video[poster], audio[src]")) {
      for (const attribute of ["src", "srcset", "poster"]) {
        const value = element.getAttribute(attribute);
        if (value && /(^|,\s*)https?:/i.test(value)) {
          element.removeAttribute(attribute);
          element.classList.add("mdv-blocked-image");
          element.title = "Vzdálený obrázek je vypnutý v nastavení";
        }
      }
    }
  }

  function rewriteURLs(root, baseURL) {
    if (!state.remoteImages) blockRemoteImages(root);
    for (const element of root.querySelectorAll("[src], [href], [poster]")) {
      for (const attribute of ["src", "href", "poster"]) {
        const value = element.getAttribute(attribute);
        if (value == null || value === "") continue;
        const resolved = resolveURL(value, baseURL, attribute === "href");
        if (resolved == null) element.removeAttribute(attribute);
        else if (resolved !== value) element.setAttribute(attribute, resolved);
      }
    }
    // <picture><source srcset media="(prefers-color-scheme: dark)"> – obrázky pro světlý a tmavý vzhled.
    for (const element of root.querySelectorAll("[srcset]")) {
      const candidates = element.getAttribute("srcset").split(",").map((candidate) => {
        const [url, ...descriptors] = candidate.trim().split(/\s+/);
        const resolved = url ? resolveURL(url, baseURL, false) : null;
        return resolved ? [resolved, ...descriptors].join(" ") : null;
      }).filter(Boolean);
      element.setAttribute("srcset", candidates.join(", "));
    }
  }

  // MARK: - Reconciliation top-level bloků

  /**
   * Nahradí obsah kontejneru novými bloky, ale nezměněné bloky (stejný klíč) ponechá –
   * včetně vyrenderovaného KaTeXu, Mermaidu a zvýraznění kódu. Vrací nové bloky.
   */
  function reconcile(container, fragment) {
    const reusable = new Map();
    for (const element of container.children) {
      const key = element.dataset.mdvKey;
      if (!key) continue;
      if (!reusable.has(key)) reusable.set(key, []);
      reusable.get(key).push(element);
    }

    const next = [];
    const fresh = [];
    for (const node of [...fragment.childNodes]) {
      let block = node;
      if (node.nodeType !== Node.ELEMENT_NODE) {
        if (node.nodeType !== Node.TEXT_NODE || !node.textContent.trim()) continue;
        block = document.createElement("div");
        block.append(node);
      }
      const key = hash(withoutSourcepos(block.outerHTML));
      const candidates = reusable.get(key);
      if (candidates && candidates.length) {
        const existing = candidates.shift();
        moveSourcepos(existing, block);
        next.push(existing);
      } else {
        block.dataset.mdvKey = key;
        next.push(block);
        fresh.push(block);
      }
    }
    container.replaceChildren(...next);
    return fresh;
  }

  /** Blok se nezměnil, ale posunul: posunout čísla řádků i u vnořených prvků. */
  function moveSourcepos(existing, incoming) {
    const delta = startLine(incoming) - startLine(existing);
    if (!delta || Number.isNaN(delta)) return;
    for (const element of withSelf(existing, "[data-sourcepos]")) {
      const shifted = element.getAttribute("data-sourcepos").replace(/(\d+)(:\d+-)(\d+)(:\d+)/, (_, a, b, c, d) =>
        `${parseInt(a, 10) + delta}${b}${parseInt(c, 10) + delta}${d}`);
      element.setAttribute("data-sourcepos", shifted);
    }
  }

  // MARK: - Kotva scrollu

  function captureAnchor() {
    const container = scroller();
    const top = container.scrollTop;
    const atBottom = container.scrollTop + container.clientHeight >= container.scrollHeight - 40;
    const occurrences = new Map();
    for (const element of content().children) {
      const key = element.dataset.mdvKey;
      occurrences.set(key, (occurrences.get(key) ?? 0) + 1);
      const elementStart = elementTop(element);
      if (elementStart + element.offsetHeight > top) {
        return {
          key,
          occurrence: occurrences.get(key) - 1,
          line: startLine(element),
          ratio: element.offsetHeight ? (top - elementStart) / element.offsetHeight : 0,
          top,
          atBottom,
        };
      }
    }
    return { top, atBottom };
  }

  function applyAnchor(anchor) {
    const container = scroller();
    if (anchor.atBottom && state.followTail) {
      container.scrollTop = container.scrollHeight;
      return;
    }
    const blocks = [...content().children];
    let target = null;
    if (anchor.key) {
      target = blocks.filter((element) => element.dataset.mdvKey === anchor.key)[anchor.occurrence] ?? null;
    }
    if (!target && !Number.isNaN(anchor.line)) {
      for (const element of blocks) {
        if (startLine(element) <= anchor.line) target = element;
      }
    }
    if (!target) {
      container.scrollTop = anchor.top;
      return;
    }
    container.scrollTop = elementTop(target) + anchor.ratio * target.offsetHeight;
  }

  /** Obrázky, Mermaid a KaTeX mění výšky ještě po aktualizaci – kotvu chvíli držet. */
  function holdAnchor(anchor) {
    releaseAnchor();
    const observer = new ResizeObserver(() => {
      applyAnchor(anchor);
      invalidateSyncMap();
      syncPanes();
    });
    observer.observe(content());
    state.hold = { observer, timer: setTimeout(releaseAnchor, 1000) };
  }

  function releaseAnchor() {
    if (!state.hold) return;
    state.hold.observer.disconnect();
    clearTimeout(state.hold.timer);
    state.hold = null;
  }

  // MARK: - Vylepšení bloků (task listy, kód, matika, Mermaid)

  function languageOf(code) {
    const match = /(?:^|\s)language-([\w#+.-]+)/.exec(code.className);
    return match ? match[1].toLowerCase() : null;
  }

  function enhanceTaskLists(block) {
    for (const item of withSelf(block, "li")) {
      const first = item.firstElementChild;
      if (first?.matches('input[type="checkbox"]')) {
        item.classList.add("task-list-item");
        first.classList.add("task-list-item-checkbox");
        item.parentElement?.classList.add("contains-task-list");
      }
    }
  }

  function highlightCode(block) {
    if (!window.hljs) return;
    for (const code of withSelf(block, "pre > code")) {
      const language = languageOf(code);
      if (!language || language === "mermaid" || language === "math" || !hljs.getLanguage(language)) continue;
      code.innerHTML = hljs.highlight(code.textContent, { language, ignoreIllegals: true }).value;
      code.classList.add("hljs");
    }
  }

  function renderMath(block) {
    if (!window.katex) return;
    for (const element of withSelf(block, ".math-inline, .math-display")) {
      const tex = element.textContent;
      try {
        katex.render(tex, element, {
          displayMode: element.classList.contains("math-display"),
          throwOnError: false,
          output: "htmlAndMathml",
          trust: false,
        });
      } catch (error) {
        element.title = String(error?.message ?? error);
      }
    }
  }

  // MARK: - Mermaid – líně podle viditelnosti, při chybě poslední platná verze

  let mermaidTheme = null;
  let diagramObserver = null;
  let diagramQueue = Promise.resolve();
  const pendingDiagrams = new Set();
  /** SVG posledních platných diagramů podle pořadí v dokumentu (agent diagram právě píše → chyba). */
  const lastGoodDiagrams = [];

  function configureMermaid() {
    const theme = prefersDark() ? "dark" : "default";
    if (theme === mermaidTheme) return;
    mermaidTheme = theme;
    mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme });
  }

  const diagramSelector = "pre > code.language-mermaid, .mdv-mermaid";

  function diagramIndex(element) {
    return [...content().querySelectorAll(diagramSelector)]
      .findIndex((candidate) => candidate === element || candidate.parentElement === element);
  }

  function diagramContainer(source, svg, error) {
    const container = document.createElement("div");
    container.className = error ? "mdv-mermaid mdv-mermaid-stale" : "mdv-mermaid";
    container.dataset.mermaidSource = source;
    container.innerHTML = svg;
    if (error) {
      const badge = document.createElement("div");
      badge.className = "mdv-mermaid-badge";
      badge.textContent = `Diagram teď nejde vykreslit (${error}). Zobrazuji poslední platnou verzi.`;
      container.prepend(badge);
    }
    return container;
  }

  async function renderMermaidElement(target, source) {
    if (!target.isConnected) return;
    configureMermaid();
    const index = diagramIndex(target);
    const id = `mdv-mermaid-${++state.mermaidCounter}`;
    let replacement = null;
    try {
      const { svg } = await mermaid.render(id, source);
      if (index >= 0) lastGoodDiagrams[index] = svg;
      replacement = diagramContainer(source, svg, null);
    } catch (error) {
      // Po chybě nechává Mermaid v <body> dočasný kontejner s chybovým SVG. Po úspěchu ne –
      // a výsledné SVG nese stejné id, takže úklid smí běžet jen tady.
      document.getElementById(`d${id}`)?.remove();
      const leftover = document.getElementById(id);
      if (leftover && !leftover.closest("#mdv-content")) leftover.remove();
      const message = String(error?.message ?? error).split("\n")[0];
      const previous = index >= 0 ? lastGoodDiagrams[index] : null;
      if (previous) {
        replacement = diagramContainer(source, previous, message);
      } else if (target.tagName === "PRE") {
        target.classList.add("mdv-mermaid-error");
        target.dataset.error = message;
      }
    }
    // Mezitím mohla přijít novější verze dokumentu a blok nahradit.
    if (!replacement || !target.isConnected) return;
    for (const attribute of ["data-mdv-key", "data-sourcepos"]) {
      if (target.hasAttribute(attribute)) replacement.setAttribute(attribute, target.getAttribute(attribute));
    }
    const container = scroller();
    const before = target.getBoundingClientRect();
    const above = before.bottom <= container.getBoundingClientRect().top;
    target.replaceWith(replacement);
    // Diagram nad viditelnou částí změnil výšku – posunout, aby text pod ním neposkočil.
    if (above) container.scrollTop += replacement.getBoundingClientRect().height - before.height;
  }

  /** Mermaid nesnese souběžné rendery – vše jde přes jednu frontu. */
  function queueDiagram(target, source) {
    diagramQueue = diagramQueue.then(() => renderMermaidElement(target, source)).catch(() => {});
    return diagramQueue;
  }

  function observeDiagrams(blocks) {
    if (!window.mermaid) return;
    diagramObserver ??= new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        diagramObserver.unobserve(entry.target);
        pendingDiagrams.delete(entry.target);
        queueDiagram(entry.target, entry.target.textContent);
      }
    }, { root: scroller(), rootMargin: "1200px 0px" });
    for (const pending of [...pendingDiagrams]) {
      if (!pending.isConnected) {
        diagramObserver.unobserve(pending);
        pendingDiagrams.delete(pending);
      }
    }
    for (const block of blocks) {
      for (const code of withSelf(block, "pre > code.language-mermaid")) {
        pendingDiagrams.add(code.parentElement);
        diagramObserver.observe(code.parentElement);
      }
    }
  }

  /** Vykreslí i diagramy mimo obrazovku (tisk, export, self-test). */
  async function flushDiagrams() {
    for (const pending of [...pendingDiagrams]) {
      diagramObserver?.unobserve(pending);
      pendingDiagrams.delete(pending);
      if (pending.isConnected) queueDiagram(pending, pending.textContent);
    }
    await diagramQueue;
  }

  function rerenderMermaidForTheme() {
    if (!window.mermaid) return;
    for (const container of [...content().querySelectorAll(".mdv-mermaid")]) {
      queueDiagram(container, container.dataset.mermaidSource);
    }
  }

  async function enhance(blocks) {
    for (const block of blocks) {
      enhanceTaskLists(block);
      highlightCode(block);
      renderMath(block);
    }
    observeDiagrams(blocks);
  }

  // MARK: - Zdrojový panel a synchronizace scrollu
  //
  // Mapa řádek ↔ y v náhledu se staví z data-sourcepos (začátek i konec každého bloku, i vnořených),
  // seřadí se a vyfiltruje na monotónní posloupnost; mezi body se interpoluje lineárně.
  // Synchronizuje se vždy z panelu, se kterým uživatel naposledy pracoval, takže nevzniká zpětná vazba.

  const sourceScroller = () => document.getElementById("mdv-source-scroll");
  const sourceContent = () => document.getElementById("mdv-source");
  const sync = { active: "preview", map: null, lineTops: null, scheduled: false, pin: null };
  const sourceVisible = () => document.body.classList.contains("mdv-with-source");

  function invalidateSyncMap() {
    sync.map = null;
    sync.lineTops = null;
  }

  function buildSyncMap() {
    const container = scroller();
    const origin = container.getBoundingClientRect().top - container.scrollTop;
    const points = [];
    for (const element of content().querySelectorAll("[data-sourcepos]")) {
      // Definice poznámek pod čarou se vykreslují na konci dokumentu, ale ve zdroji jsou uprostřed –
      // bod mimo pořadí by zablokoval monotónní mapu za sebou.
      if (element.closest(".footnotes")) continue;
      const match = /^(\d+):\d+-(\d+):\d+/.exec(element.getAttribute("data-sourcepos"));
      const rect = element.getBoundingClientRect();
      if (!match || !rect.height) continue;
      const top = rect.top - origin;
      points.push([parseInt(match[1], 10), top]);
      points.push([parseInt(match[2], 10) + 1, top + rect.height]);
    }
    points.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    const map = [[1, 0]];
    for (const point of points) {
      const last = map[map.length - 1];
      if (point[0] >= last[0] && point[1] >= last[1]) map.push(point);
    }
    return map;
  }

  /** Lineární interpolace v monotónní mapě: hledá se podle sloupce `from`, vrací sloupec `to`. */
  function interpolate(map, value, from, to) {
    let low = 0;
    let high = map.length - 1;
    if (value <= map[0][from]) return map[0][to];
    if (value >= map[high][from]) return map[high][to];
    while (high - low > 1) {
      const middle = (low + high) >> 1;
      if (map[middle][from] <= value) low = middle;
      else high = middle;
    }
    const a = map[low];
    const b = map[high];
    if (b[from] === a[from]) return b[to];
    return a[to] + (value - a[from]) / (b[from] - a[from]) * (b[to] - a[to]);
  }

  function sourceLineTops() {
    if (!sync.lineTops) {
      sync.lineTops = [...sourceContent().children].map((line) => [line.offsetTop, line.offsetHeight]);
    }
    return sync.lineTops;
  }

  /** Zlomkový řádek zdroje na dané y ve zdrojovém panelu. */
  function sourceLineAt(y) {
    const tops = sourceLineTops();
    if (!tops.length) return 1;
    let low = 0;
    let high = tops.length - 1;
    while (low < high) {
      const middle = (low + high + 1) >> 1;
      if (tops[middle][0] <= y) low = middle;
      else high = middle - 1;
    }
    const [top, height] = tops[low];
    return low + 1 + Math.min(1, Math.max(0, height ? (y - top) / height : 0));
  }

  function sourceYForLine(line) {
    const tops = sourceLineTops();
    if (!tops.length) return 0;
    const index = Math.min(tops.length - 1, Math.max(0, Math.floor(line) - 1));
    const [top, height] = tops[index];
    return top + (line - Math.floor(line)) * height;
  }

  /**
   * Spojí volání v rámci jedné úlohy přes microtask. Ne requestAnimationFrame: ten WebKit
   * v zakrytých oknech pozastavuje, a scroll události stejně chodí nejvýš jednou za snímek.
   */
  function syncPanes() {
    if (!sourceVisible() || sync.scheduled) return;
    sync.scheduled = true;
    queueMicrotask(() => {
      sync.scheduled = false;
      sync.map ??= buildSyncMap();
      // Skok na řádek (osnova): zdroj ukáže přesně cílový řádek, ne interpolaci okraje nad blokem.
      if (sync.pin && performance.now() < sync.pin.until) {
        sourceScroller().scrollTop = sourceYForLine(sync.pin.line);
        return;
      }
      sync.pin = null;
      if (sync.active === "source") {
        const line = sourceLineAt(sourceScroller().scrollTop);
        scroller().scrollTop = interpolate(sync.map, line, 0, 1);
      } else {
        const line = interpolate(sync.map, scroller().scrollTop, 1, 0);
        sourceScroller().scrollTop = sourceYForLine(line);
      }
    });
  }

  function setSource(options) {
    document.body.classList.toggle("mdv-with-source", !!options.visible);
    if (options.width) document.body.style.setProperty("--mdv-source-width", `${(options.width * 100).toFixed(1)}%`);
    invalidateSyncMap();
    syncPanes();
  }

  function updateSource(html) {
    const keepLine = sync.active === "source" ? sourceLineAt(sourceScroller().scrollTop) : null;
    sourceContent().innerHTML = html;
    invalidateSyncMap();
    if (keepLine != null) sourceScroller().scrollTop = sourceYForLine(keepLine);
  }

  function setupDivider() {
    const divider = document.getElementById("mdv-divider");
    divider.addEventListener("pointerdown", (event) => {
      divider.setPointerCapture(event.pointerId);
      let ratio = null;
      const move = (moveEvent) => {
        ratio = Math.min(0.8, Math.max(0.15, moveEvent.clientX / window.innerWidth));
        document.body.style.setProperty("--mdv-source-width", `${(ratio * 100).toFixed(1)}%`);
        invalidateSyncMap();
        syncPanes();
      };
      const up = () => {
        divider.removeEventListener("pointermove", move);
        divider.removeEventListener("pointerup", up);
        if (ratio != null) post({ type: "sourceWidth", value: ratio });
      };
      divider.addEventListener("pointermove", move);
      divider.addEventListener("pointerup", up);
    });
  }

  // MARK: - Hledání (CSS Custom Highlight API)

  const search = { query: "", options: {}, ranges: [], index: -1 };

  function normalizeForSearch(text, options) {
    let result = options.matchCase ? text : text.toLowerCase();
    if (options.ignoreDiacritics !== false) result = result.normalize("NFD").replace(/\p{M}/gu, "");
    return result;
  }

  /** Text obsahu + mapa znaků normalizovaného textu zpět na (uzel, offset, délka). */
  function searchIndex(options) {
    const walker = document.createTreeWalker(content(), NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => node.parentElement?.closest(".katex-mathml, style, script, .mdv-mermaid-badge")
        ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
    });
    let text = "";
    const map = [];
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const value = node.nodeValue;
      for (let offset = 0; offset < value.length;) {
        const codePoint = value.codePointAt(offset);
        const length = codePoint > 0xffff ? 2 : 1;
        for (const character of normalizeForSearch(value.slice(offset, offset + length), options)) {
          text += character;
          map.push([node, offset, length]);
        }
        offset += length;
      }
    }
    return { text, map };
  }

  function updateFindStatus() {
    const status = document.getElementById("mdv-find-status");
    if (!search.query) {
      status.hidden = true;
      return;
    }
    status.hidden = false;
    status.textContent = search.ranges.length ? `${search.index + 1} / ${search.ranges.length}` : "Nenalezeno";
  }

  function paintFind() {
    if (typeof CSS === "undefined" || !CSS.highlights) return;
    CSS.highlights.delete("mdv-find");
    CSS.highlights.delete("mdv-find-current");
    if (search.ranges.length) {
      CSS.highlights.set("mdv-find", new Highlight(...search.ranges));
      CSS.highlights.set("mdv-find-current", new Highlight(search.ranges[search.index]));
    }
    updateFindStatus();
  }

  function revealCurrentMatch() {
    const range = search.ranges[search.index];
    if (!range) return;
    releaseAnchor();
    const container = scroller();
    const rect = range.getBoundingClientRect();
    const bounds = container.getBoundingClientRect();
    if (rect.top < bounds.top + 40 || rect.bottom > bounds.bottom - 40) {
      container.scrollTop += rect.top - bounds.top - bounds.height / 3;
    }
    sync.active = "preview";
    syncPanes();
  }

  function runSearch(keepPosition) {
    const previous = keepPosition ? search.ranges[search.index]?.getBoundingClientRect().top : null;
    search.ranges = [];
    const needle = normalizeForSearch(search.query, search.options);
    if (needle) {
      const { text, map } = searchIndex(search.options);
      for (let at = text.indexOf(needle); at !== -1 && search.ranges.length < 10000; at = text.indexOf(needle, at + needle.length)) {
        const first = map[at];
        const last = map[at + needle.length - 1];
        const range = document.createRange();
        range.setStart(first[0], first[1]);
        range.setEnd(last[0], last[1] + last[2]);
        search.ranges.push(range);
      }
    }
    if (!search.ranges.length) {
      search.index = -1;
    } else if (previous != null) {
      // Po reloadu zůstat u výsledku nejblíž původní pozici.
      let best = 0;
      search.ranges.forEach((range, index) => {
        if (Math.abs(range.getBoundingClientRect().top - previous) < Math.abs(search.ranges[best].getBoundingClientRect().top - previous)) best = index;
      });
      search.index = best;
    } else {
      // První výsledek od aktuální pozice čtení.
      const top = scroller().getBoundingClientRect().top;
      const index = search.ranges.findIndex((range) => range.getBoundingClientRect().bottom >= top);
      search.index = index === -1 ? 0 : index;
    }
    paintFind();
  }

  function find(query, options) {
    search.query = query ?? "";
    search.options = options ?? {};
    runSearch(false);
    revealCurrentMatch();
    return { count: search.ranges.length, index: search.index };
  }

  function findStep(delta) {
    if (search.ranges.length) {
      search.index = (search.index + delta + search.ranges.length) % search.ranges.length;
      paintFind();
      revealCurrentMatch();
    }
    return { count: search.ranges.length, index: search.index };
  }

  // MARK: - Export

  /** Obsah pro export: všechny diagramy vykreslené, bez interních atributů. */
  async function exportContent() {
    await flushDiagrams();
    const clone = content().cloneNode(true);
    for (const element of clone.querySelectorAll("[data-mdv-key], [data-sourcepos], [data-mermaid-source]")) {
      element.removeAttribute("data-mdv-key");
      element.removeAttribute("data-sourcepos");
      element.removeAttribute("data-mermaid-source");
    }
    return {
      html: clone.innerHTML,
      title: content().querySelector("h1")?.textContent?.trim() ?? "",
    };
  }

  // MARK: - Tisk

  /** Nadpis + následující blok do nedělitelného obalu (jen po dobu tisku). */
  function preparePrint() {
    finishPrint();
    for (const heading of [...content().querySelectorAll(":scope > h1, :scope > h2, :scope > h3, :scope > h4, :scope > h5, :scope > h6")]) {
      const next = heading.nextElementSibling;
      if (!next || /^H[1-6]$/.test(next.tagName)) continue;
      const keep = document.createElement("div");
      keep.className = "mdv-print-keep";
      heading.before(keep);
      keep.append(heading, next);
    }
  }

  function finishPrint() {
    for (const keep of [...content().querySelectorAll(":scope > .mdv-print-keep")]) {
      keep.replaceWith(...keep.childNodes);
    }
  }

  // MARK: - API pro Swift

  async function update(payload) {
    const generation = ++state.generation;
    setupPurify();
    state.remoteImages = payload.remoteImages !== false;
    // Se zdrojovým panelem, se kterým uživatel pracuje, vede zdroj; jinak kotva v náhledu.
    const sourceLeads = sourceVisible() && sync.active === "source";
    const anchor = state.hasContent && !sourceLeads ? captureAnchor() : null;

    const fragment = DOMPurify.sanitize(payload.html, purifyConfig);
    rewriteURLs(fragment, payload.baseURL);
    const fresh = reconcile(content(), fragment);
    if (typeof payload.sourceHTML === "string") updateSource(payload.sourceHTML);

    if (anchor) {
      applyAnchor(anchor);
      holdAnchor(anchor);
    } else if (!state.hasContent && payload.restoreLine) {
      scrollToLine(payload.restoreLine);
    }
    if (!state.hasContent) scroller().focus({ preventScroll: true });
    state.hasContent = true;

    await enhance(fresh);
    if (search.query) runSearch(true);
    invalidateSyncMap();
    syncPanes();
    return { generation, fresh: fresh.length, total: content().children.length };
  }

  function setStatus(status) {
    const banner = document.getElementById("mdv-banner");
    banner.textContent = status?.message ?? "";
    banner.hidden = !status?.message;
  }

  /** Skok na blok, který obsahuje daný řádek zdroje (TOC, obnovení pozice). */
  function scrollToLine(line) {
    // Navigace ruší držení kotvy z poslední aktualizace, jinak by ji ResizeObserver vrátil zpět.
    releaseAnchor();
    let target = null;
    for (const element of content().querySelectorAll("[data-sourcepos]")) {
      if (startLine(element) <= line) target = element;
      else break;
    }
    if (target) scroller().scrollTop = elementTop(target) - 8;
    sync.active = "preview";
    sync.pin = { line, until: performance.now() + 600 };
    syncPanes();
  }

  function scrollToFragment(fragment) {
    let id = fragment;
    try {
      id = decodeURIComponent(fragment);
    } catch (error) {
      // Neplatné kódování – zkusíme původní hodnotu.
    }
    const target = document.getElementById(id) ?? document.getElementsByName(id)[0];
    if (!target) return;
    releaseAnchor();
    // Kotva nadpisu je prázdný <a> uvnitř nadpisu – cílem je celý nadpis.
    const heading = target.closest("h1, h2, h3, h4, h5, h6") ?? target;
    scroller().scrollTop = elementTop(heading) - 8;
    sync.active = "preview";
    syncPanes();
  }

  /** První viditelný řádek zdroje – pro uložení pozice a zvýraznění v TOC. */
  function topLine() {
    const top = scroller().scrollTop;
    let line = 1;
    for (const element of content().children) {
      if (elementTop(element) + element.offsetHeight > top) {
        const start = startLine(element);
        return Number.isNaN(start) ? line : start;
      }
      const start = startLine(element);
      if (!Number.isNaN(start)) line = start;
    }
    return line;
  }

  // MARK: - Události

  function handleLinkEvent(event) {
    const link = event.target.closest?.("a[href]");
    if (!link) return;
    event.preventDefault();
    const href = link.getAttribute("href");
    if (href.startsWith("#")) {
      scrollToFragment(href.slice(1));
      return;
    }
    post({ type: "link", href: link.href, newWindow: event.metaKey || event.button === 1 });
  }

  document.addEventListener("click", handleLinkEvent, true);
  document.addEventListener("auxclick", handleLinkEvent, true);

  let scrollTimer = null;
  scroller().addEventListener("scroll", () => {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(() => post({ type: "scroll", line: topLine() }), 250);
  }, { passive: true });

  for (const type of ["wheel", "keydown", "mousedown", "touchstart"]) {
    scroller().addEventListener(type, releaseAnchor, { passive: true });
  }

  // Aktivní je panel, se kterým uživatel naposledy pracoval; jen ten řídí synchronizaci.
  for (const [element, pane] of [[scroller(), "preview"], [sourceScroller(), "source"]]) {
    for (const type of ["wheel", "keydown", "mousedown", "touchstart"]) {
      element.addEventListener(type, () => {
        sync.active = pane;
        sync.pin = null;
      }, { passive: true, capture: true });
    }
    element.addEventListener("scroll", () => {
      if (sync.active === pane) syncPanes();
    }, { passive: true });
  }

  new ResizeObserver(() => {
    invalidateSyncMap();
    syncPanes();
  }).observe(content());
  setupDivider();

  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    rerenderMermaidForTheme();
  });

  window.addEventListener("error", (event) => post({ type: "error", message: String(event.message) }));

  globalThis.mdv = {
    update,
    setStatus,
    scrollToLine,
    topLine,
    flushDiagrams,
    setFollowTail: (value) => { state.followTail = !!value; },
    setSource,
    find,
    findStep,
    selectionText: () => window.getSelection()?.toString() ?? "",
    exportContent,
    preparePrint,
    finishPrint,
    sourceTopLine: () => sourceLineAt(sourceScroller().scrollTop),
  };

  post({ type: "ready" });
})();
