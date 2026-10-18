"""mitmproxy addon: route browser AI-chat prompts through the Varman content firewall.

For POST requests to the consumer chat backends, send the request body to the
Kyte sidecar's /cf/check; if it returns non-200 (a rule matched), block the
request with 403 before it leaves the browser. Reuses the SAME firewall engine,
rules, and signed evidence as the API-host data plane -- just a browser-shaped
front end.

Run:   mitmdump -p 8081 -s /Users/kamlesh/kytelang/varman/.e2e/cf_mitm.py
Then point the browser/OS HTTP+HTTPS proxy at 127.0.0.1:8081 and trust the
mitmproxy CA (http://mitm.it while the proxy is running, or add
~/.mitmproxy/mitmproxy-ca-cert.pem to the keychain).
"""
import urllib.request, urllib.error, urllib.parse, time
from mitmproxy import http

CF = "http://127.0.0.1:8899/cf/check"
LOG = "/Users/kamlesh/kytelang/varman/.e2e/mitm.log"

def _log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(msg + "\n")
    except Exception:
        pass

def _decoded(body: str) -> str:
    # Web apps URL/form-encode the prompt (spaces -> '+' or '%20'), which breaks
    # the card/number detectors. Decode first so the firewall sees the real text.
    try:
        return urllib.parse.unquote_plus(body)
    except Exception:
        return body
# Host suffixes whose POST bodies carry user prompts.
TARGETS = ("chatgpt.com", "chat.openai.com", "gemini.google.com",
           "claude.ai", "generativelanguage.googleapis.com", "api.openai.com", "api.anthropic.com")

def _targeted(host: str) -> bool:
    return any(host == t or host.endswith("." + t) or host.endswith(t) for t in TARGETS)

def request(flow: http.HTTPFlow) -> None:
    if flow.request.method != "POST":
        return
    if not _targeted(flow.request.host):
        return
    body = flow.request.get_text(strict=False) or ""
    if not body.strip():
        return
    body = _decoded(body)
    _log("%s POST %s%s  (%d bytes)" % (time.strftime("%H:%M:%S"), flow.request.host, flow.request.path[:40], len(body)))
    try:
        req = urllib.request.Request(CF, data=body.encode("utf-8", "ignore"),
                                     method="POST",
                                     headers={"content-type": "text/plain"})
        with urllib.request.urlopen(req, timeout=5) as r:
            code = r.status
    except urllib.error.HTTPError as e:
        code = e.code                 # 403 = a rule matched -> block
    except Exception:
        code = 200                    # inspector unreachable: fail-open so browsing is not broken (demo choice)
    if code != 200:
        flow.response = http.Response.make(
            403, b"blocked by content policy (Varman)\n",
            {"content-type": "text/plain", "x-acp-content-verdict": "deny"})
