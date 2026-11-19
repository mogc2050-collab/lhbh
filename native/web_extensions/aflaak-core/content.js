/* Aflaak Core content script.
 * Talks to the app through a native port named "aflaak" and executes the
 * commands the app sends (dark page, reader view). */
(function () {
  "use strict";
  if (window.__aflaakCore) return;
  window.__aflaakCore = true;

  const DARK_ID = "aflaak-dark-overlay";

  function setDark(on) {
    const existing = document.getElementById(DARK_ID);
    if (!on) {
      if (existing) existing.remove();
      return;
    }
    if (existing) return;
    const style = document.createElement("style");
    style.id = DARK_ID;
    style.textContent =
      "html{filter:invert(0.88) hue-rotate(180deg)!important}" +
      "img,video,canvas,svg,picture{filter:invert(1) hue-rotate(180deg)!important}";
    (document.head || document.documentElement).appendChild(style);
  }

  function pickArticle() {
    const direct =
      document.querySelector("article") ||
      document.querySelector("[role=main]") ||
      document.querySelector("main");
    if (direct && direct.innerText.trim().length > 400) return direct;
    // Fallback: the block with the most paragraph text.
    let best = null;
    let bestScore = 0;
    document.querySelectorAll("div,section").forEach(function (el) {
      let score = 0;
      el.querySelectorAll(":scope > p").forEach(function (p) {
        score += p.innerText.trim().length;
      });
      if (score > bestScore) {
        best = el;
        bestScore = score;
      }
    });
    return best || document.body;
  }

  function isRtlText(text) {
    const sample = text.slice(0, 400);
    const rtl = (sample.match(/[\u0590-\u08FF]/g) || []).length;
    return rtl > sample.length * 0.3;
  }

  function reader() {
    const source = pickArticle();
    const clone = source.cloneNode(true);
    clone
      .querySelectorAll(
        "script,style,nav,aside,header,footer,iframe,button,form,noscript,[aria-hidden=true]"
      )
      .forEach(function (e) { e.remove(); });
    const title = document.title || "";
    const rtl = isRtlText(clone.innerText || "");
    document.documentElement.setAttribute("dir", rtl ? "rtl" : "ltr");
    document.body.innerHTML = "";
    document.body.style.cssText =
      "margin:0 auto;padding:22px;max-width:760px;" +
      "font-family:system-ui,'Noto Sans Arabic',sans-serif;font-size:19px;" +
      "line-height:1.85;background:#fbfaf7;color:#232323;filter:none";
    const h = document.createElement("h1");
    h.textContent = title;
    h.style.cssText = "font-size:26px;line-height:1.4;margin:0 0 18px";
    document.body.appendChild(h);
    document.body.appendChild(clone);
    document.querySelectorAll("img").forEach(function (img) {
      img.style.maxWidth = "100%";
      img.style.height = "auto";
    });
  }

  const handlers = {
    dark: function (args) { setDark(!!(args && args.on)); },
    reader: function () { reader(); },
  };

  try {
    const port = browser.runtime.connectNative("aflaak");
    port.onMessage.addListener(function (msg) {
      if (!msg || typeof msg.cmd !== "string") return;
      const handler = handlers[msg.cmd];
      if (handler) handler(msg.args || {});
    });
  } catch (e) {
    // Native messaging unavailable (not running inside the app).
  }
})();
