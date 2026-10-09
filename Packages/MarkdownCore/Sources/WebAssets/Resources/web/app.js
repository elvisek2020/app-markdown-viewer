// MDView – logika náhledu.
//
// Běží jako WKUserScript v izolovaném WKContentWorld „mdview“. JavaScript stránky
// (tj. cokoli z Markdown dokumentu) je vypnutý přes allowsContentJavaScript = false,
// DOM je sdílený, globální proměnné ne. Knihovny (DOMPurify, highlight.js, KaTeX,
// Mermaid) vkládá Swift do stejného worldu, ty větší líně podle obsahu dokumentu.
//
// Swift volá: mdv.update(payload), mdv.setStatus(status), mdv.scrollToLine(line), mdv.setFollowTail(bool)
// Swift dostává: { type: "ready" | "link" | "scroll" | "error", … } přes webkit.messageHandlers.mdv

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
    FORBID_ATTR: ["style", "target", "formaction", "srcset"],
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

  /** Relativní URL → absolutní `mdv-file://` vůči adresáři dokumentu (bez `<base>`, kvůli #kotvám). */
  function rewriteURLs(root, baseURL) {
    for (const element of root.querySelectorAll("[src], [href], [poster]")) {
      for (const attribute of ["src", "href", "poster"]) {
        const value = element.getAttribute(attribute);
        if (value == null || value === "" || value.startsWith("#")) continue;
        if (value.startsWith("//")) {
          element.setAttribute(attribute, "https:" + value);
        } else if (/^file:/i.test(value)) {
          // Obrázky z file: URL načte jen náš handler; odkazy řeší Swift (Reveal in Finder).
          if (attribute !== "href") element.setAttribute(attribute, value.replace(/^file:/i, "mdv-file:"));
        } else if (!/^[a-z][a-z0-9+.-]*:/i.test(value)) {
          try {
            element.setAttribute(attribute, new URL(value, baseURL).href);
          } catch (error) {
            element.removeAttribute(attribute);
          }
        }
      }
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
    const observer = new ResizeObserver(() => applyAnchor(anchor));
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

  let mermaidTheme = null;

  function configureMermaid() {
    const theme = prefersDark() ? "dark" : "default";
    if (theme === mermaidTheme) return;
    mermaidTheme = theme;
    mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme });
  }

  async function renderMermaidElement(target, source) {
    const id = `mdv-mermaid-${++state.mermaidCounter}`;
    try {
      const { svg } = await mermaid.render(id, source);
      const container = document.createElement("div");
      container.className = "mdv-mermaid";
      container.dataset.mermaidSource = source;
      for (const attribute of ["data-mdv-key", "data-sourcepos"]) {
        if (target.hasAttribute(attribute)) container.setAttribute(attribute, target.getAttribute(attribute));
      }
      container.innerHTML = svg;
      target.replaceWith(container);
    } catch (error) {
      if (target.tagName === "PRE") {
        target.classList.add("mdv-mermaid-error");
        target.dataset.error = String(error?.message ?? error).split("\n")[0];
      }
      // Po chybě nechává Mermaid v <body> dočasný kontejner s chybovým SVG. Po úspěchu ne –
      // a výsledné SVG nese stejné id, takže úklid smí běžet jen tady.
      document.getElementById(`d${id}`)?.remove();
      const leftover = document.getElementById(id);
      if (leftover && !leftover.closest("#mdv-content")) leftover.remove();
    }
  }

  async function renderMermaid(blocks) {
    if (!window.mermaid) return;
    configureMermaid();
    for (const block of blocks) {
      for (const code of withSelf(block, "pre > code.language-mermaid")) {
        if (!code.isConnected) continue;
        await renderMermaidElement(code.parentElement, code.textContent);
      }
    }
  }

  async function rerenderMermaidForTheme() {
    if (!window.mermaid) return;
    configureMermaid();
    for (const container of [...content().querySelectorAll(".mdv-mermaid")]) {
      await renderMermaidElement(container, container.dataset.mermaidSource);
    }
  }

  async function enhance(blocks) {
    for (const block of blocks) {
      enhanceTaskLists(block);
      highlightCode(block);
      renderMath(block);
    }
    await renderMermaid(blocks);
  }

  // MARK: - API pro Swift

  async function update(payload) {
    const generation = ++state.generation;
    setupPurify();
    const anchor = state.hasContent ? captureAnchor() : null;

    const fragment = DOMPurify.sanitize(payload.html, purifyConfig);
    rewriteURLs(fragment, payload.baseURL);
    const fresh = reconcile(content(), fragment);

    if (anchor) {
      applyAnchor(anchor);
      holdAnchor(anchor);
    } else if (payload.restoreLine) {
      scrollToLine(payload.restoreLine);
    }
    state.hasContent = true;

    await enhance(fresh);
    return { generation, fresh: fresh.length, total: content().children.length };
  }

  function setStatus(status) {
    const banner = document.getElementById("mdv-banner");
    banner.textContent = status?.message ?? "";
    banner.hidden = !status?.message;
  }

  /** Skok na blok, který obsahuje daný řádek zdroje (TOC, obnovení pozice). */
  function scrollToLine(line) {
    let target = null;
    for (const element of content().querySelectorAll("[data-sourcepos]")) {
      if (startLine(element) <= line) target = element;
      else break;
    }
    if (target) scroller().scrollTop = elementTop(target) - 8;
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
    // Kotva nadpisu je prázdný <a> uvnitř nadpisu – cílem je celý nadpis.
    const heading = target.closest("h1, h2, h3, h4, h5, h6") ?? target;
    scroller().scrollTop = elementTop(heading) - 8;
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

  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    rerenderMermaidForTheme();
  });

  window.addEventListener("error", (event) => post({ type: "error", message: String(event.message) }));

  globalThis.mdv = {
    update,
    setStatus,
    scrollToLine,
    topLine,
    setFollowTail: (value) => { state.followTail = !!value; },
  };

  post({ type: "ready" });
})();
