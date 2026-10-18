// ISOLATED-world bridge: relays verdict requests from the page hook (MAIN world)
// to the extension service worker, which is the one allowed to call the local
// firewall at http://127.0.0.1:8899 without a page-CORS preflight.
window.addEventListener("message", function (e) {
  if (e.source !== window || !e.data || e.data.__vcf !== "check") return;
  var id = e.data.id, text = e.data.text;
  try {
    chrome.runtime.sendMessage({ type: "check", text: text }, function (resp) {
      window.postMessage({
        __vcf: "verdict",
        id: id,
        deny: !!(resp && resp.deny),
        rule: (resp && resp.rule) || ""
      }, "*");
    });
  } catch (_) {
    // extension context gone: fail open so the page keeps working
    window.postMessage({ __vcf: "verdict", id: id, deny: false, rule: "" }, "*");
  }
});
