// MAIN-world hook: override window.fetch (and XHR) so every prompt the chat UI
// sends is first checked against the local Varman content firewall. Runs at
// document_start, BEFORE the page's own scripts capture fetch, so our wrapper is
// the one in effect. On a deny we return a synthetic 403 and the prompt never
// leaves the browser. The actual /cf/check call is made by the extension's
// service worker (via bridge.js) so there is no page-origin CORS problem.
(function () {
  "use strict";
  // Match the actual PROMPT-CARRYING endpoints, not whole hosts. Matching the
  // host blocked every telemetry/auth POST too (ChatGPT appeared to block every
  // message); and Gemini's send uses a RELATIVE url, so a host regex never
  // matched it. We resolve relative urls to absolute, then test these paths.
  var SEND_RE = new RegExp(
    "(batchexecute" +                                             // Gemini
    "|/backend-api/(conversation|f/conversation)" +               // ChatGPT
    "|/backend-alt/conversation" +                                // ChatGPT (alt)
    "|StreamGenerate|generateContent" +                           // Gemini API / GenAI
    "|/api/organizations/[^/]+/chat_conversations/[^/]+/(completion|retry_completion)" + // Claude.ai
    "|/append_message" +                                          // Claude.ai
    "|/v1/messages|/v1/chat/completions)",                        // dev APIs
    "i");

  function resolveUrl(u) {
    try { return new URL(u, location.href).href; } catch (_) { return String(u || ""); }
  }
  function targeted(u) {
    if (!u) return false;
    return SEND_RE.test(resolveUrl(u));
  }

  var pending = new Map(), seq = 0;

  window.addEventListener("message", function (e) {
    if (e.source !== window || !e.data || e.data.__vcf !== "verdict") return;
    var res = pending.get(e.data.id);
    if (res) { pending.delete(e.data.id); res(e.data); }
  });

  // Ask the service worker (through bridge.js) for a verdict; resolve open
  // after a short timeout so a slow/absent firewall never hangs the page.
  function ask(text) {
    return new Promise(function (resolve) {
      var id = ++seq;
      pending.set(id, resolve);
      window.postMessage({ __vcf: "check", id: id, text: text }, "*");
      setTimeout(function () {
        if (pending.has(id)) { pending.delete(id); resolve({ deny: false }); }
      }, 4000);
    });
  }

  function banner(rule) {
    try {
      var b = document.getElementById("__vcf_banner");
      if (!b) {
        b = document.createElement("div");
        b.id = "__vcf_banner";
        b.style.cssText = "position:fixed;top:0;left:0;right:0;z-index:2147483647;" +
          "background:#b00020;color:#fff;font:600 14px system-ui,sans-serif;" +
          "padding:10px 16px;text-align:center;box-shadow:0 2px 10px rgba(0,0,0,.35)";
        (document.body || document.documentElement).appendChild(b);
      }
      b.textContent = "⛔ Varman content firewall blocked this prompt" +
        (rule ? " (" + rule + ")" : "") + " — it was not sent.";
      b.style.display = "block";
      clearTimeout(b.__t);
      b.__t = setTimeout(function () { b.style.display = "none"; }, 6000);
    } catch (_) {}
  }

  function urlOf(input) {
    return typeof input === "string" ? input : (input && input.url) || "";
  }

  async function bodyText(input, init) {
    try {
      if (init && init.body != null) {
        if (typeof init.body === "string") return init.body;
        if (init.body instanceof URLSearchParams) return init.body.toString();
        try { return JSON.stringify(init.body); } catch (_) { return String(init.body); }
      }
      if (typeof Request !== "undefined" && input instanceof Request) {
        return await input.clone().text();
      }
    } catch (_) {}
    return "";
  }

  var origFetch = window.fetch;
  window.fetch = async function (input, init) {
    try {
      var url = urlOf(input);
      if (targeted(url)) {
        var body = await bodyText(input, init);
        if (body && body.length > 0) {
          var v = await ask(body);
          if (v && v.deny) {
            banner(v.rule || "content policy");
            return new Response("blocked by content policy (Varman)\n", {
              status: 403, statusText: "Blocked",
              headers: { "content-type": "text/plain", "x-acp-content-verdict": "deny" }
            });
          }
        }
      }
    } catch (_) {}
    return origFetch.apply(this, arguments);
  };

  // --- XHR path (Gemini's batchexecute and other XHR-based RPC) ---------------
  // The page (a public HTTPS origin) cannot call 127.0.0.1 itself — Chrome's
  // Private Network Access blocks it. Only the extension service worker can
  // reach the firewall, and that bridge is async. XHR.send() is a sync API, but
  // the caller only needs its onload/onreadystatechange to eventually fire, so
  // we DEFER the real send until the async verdict returns: allow -> forward;
  // deny -> synthesise a 403 completion so the prompt never leaves.
  function bodyToString(body) {
    try {
      if (body == null) return "";
      if (typeof body === "string") return body;
      if (body instanceof URLSearchParams) return body.toString();
      return "";
    } catch (_) { return ""; }
  }

  function synth403(xhr) {
    try {
      Object.defineProperty(xhr, "readyState", { value: 4, configurable: true });
      Object.defineProperty(xhr, "status", { value: 403, configurable: true });
      Object.defineProperty(xhr, "statusText", { value: "Blocked", configurable: true });
      Object.defineProperty(xhr, "responseText", { value: "blocked by content policy (Varman)", configurable: true });
      Object.defineProperty(xhr, "response", { value: "blocked by content policy (Varman)", configurable: true });
    } catch (_) {}
    try { xhr.dispatchEvent(new Event("readystatechange")); } catch (_) {}
    try { xhr.dispatchEvent(new Event("load")); } catch (_) {}
    try { xhr.dispatchEvent(new Event("loadend")); } catch (_) {}
    if (typeof xhr.onreadystatechange === "function") { try { xhr.onreadystatechange(); } catch (_) {} }
    if (typeof xhr.onload === "function") { try { xhr.onload(); } catch (_) {} }
  }

  var OrigOpen = XMLHttpRequest.prototype.open;
  var OrigSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__vcfUrl = url;
    return OrigOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function (body) {
    try {
      var url = this.__vcfUrl || "";
      if (targeted(url)) {
        var text = bodyToString(body);
        if (text && text.length > 0) {
          var self = this, args = arguments;
          ask(text).then(function (v) {           // SW decodes + checks the firewall
            if (v && v.deny) { banner(v.rule || "content policy"); synth403(self); }
            else { OrigSend.apply(self, args); }   // allowed -> forward the real request
          });
          return;                                  // defer until the verdict lands
        }
      }
    } catch (_) {}
    return OrigSend.apply(this, arguments);
  };

  console.log("[Varman] content-firewall hook active (fetch + XHR) on " + location.host);
})();
