// Service worker: performs the actual firewall check. Because it runs in the
// extension context with host_permissions for 127.0.0.1:8899, its fetch is not
// subject to the chat page's CORS. Fails OPEN (allow) if the firewall is
// unreachable, so the extension never bricks the user's browsing.
var CF = "http://127.0.0.1:8899/cf/check";

// Web apps URL/form-encode prompts (spaces -> '+' or '%20'), which would hide a
// card/number from the detectors. Decode first, same as the data-plane path.
function decodeBody(s) {
  try { return decodeURIComponent(String(s).replace(/\+/g, " ")); }
  catch (_) { return String(s); }
}

chrome.runtime.onMessage.addListener(function (msg, sender, sendResponse) {
  if (!msg || msg.type !== "check") return;
  var body = decodeBody(msg.text || "");
  fetch(CF, {
    method: "POST",
    headers: { "content-type": "text/plain" },
    body: body
  }).then(function (r) {
    sendResponse({ deny: r.status !== 200, rule: r.headers.get("x-acp-content-verdict") || "" });
  }).catch(function () {
    sendResponse({ deny: false }); // firewall down -> fail open
  });
  return true; // keep the message channel open for the async sendResponse
});
