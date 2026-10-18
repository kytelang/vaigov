#!/usr/bin/env bash
# Transparent interception for the governed AI endpoints. Run with sudo:
#   sudo bash /Users/kamlesh/kytelang/varman/.e2e/transparent-up.sh
# Reversible with transparent-down.sh. Needs the control plane (:8080) and
# sidecar (:8899) already running (they are).
#
# On each run it re-resolves the providers' real IPs (via 8.8.8.8, which ignores
# /etc/hosts) and pins the Envoy upstream clusters to those IPs. This is what
# stops the loop: the governed hostnames are redirected to localhost in
# /etc/hosts for CLIENTS, but Envoy's own upstreams must reach the REAL provider,
# so they are pinned by IP, never by a name that /etc/hosts would hijack.
set -e
E=/Users/kamlesh/kytelang/varman/.e2e
CFG="$E/envoy-transparent.yaml"
ENVOY=/Users/kamlesh/.local/share/func-e/envoy-versions/1.39.2/bin/envoy
HOSTS=(api.anthropic.com api.openai.com generativelanguage.googleapis.com)

if [ "$(id -u)" != "0" ]; then echo "run with sudo"; exit 1; fi

echo "1/4 re-resolving real provider IPs via 8.8.8.8 and pinning upstreams ..."
python3 - "$CFG" <<'PY'
import subprocess, sys, re
cfg = sys.argv[1]
# cluster name -> hostname
want = {"anthropic":"api.anthropic.com","openai":"api.openai.com","gemini":"generativelanguage.googleapis.com"}
def resolve(h):
    out = subprocess.run(["dig","+short","@8.8.8.8",h,"A"],capture_output=True,text=True).stdout
    for line in out.splitlines():
        line=line.strip()
        if re.match(r'^\d+\.\d+\.\d+\.\d+$', line):
            return line
    return None
text = open(cfg).read()
for cname,host in want.items():
    ip = resolve(host)
    if not ip:
        print(f"  WARN: could not resolve {host}; leaving existing IP"); continue
    # replace the socket_address IP inside the named cluster's endpoint block
    pat = re.compile(r'(- name: '+re.escape(cname)+r'\b.*?socket_address: \{ address: )\d+\.\d+\.\d+\.\d+(, port_value: 443 \} \} \})', re.S)
    new, n = pat.subn(r'\g<1>'+ip+r'\g<2>', text)
    if n:
        text = new; print(f"  {cname:10s} -> {ip}")
    else:
        print(f"  WARN: cluster '{cname}' endpoint not patched (pattern miss)")
open(cfg,"w").write(text)
PY

echo "2/4 trusting the demo CA in the system keychain ..."
security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$E/ca.crt"

echo "3/4 redirecting governed hosts to localhost in /etc/hosts ..."
for h in "${HOSTS[@]}"; do
  grep -q "^127.0.0.1 $h\$" /etc/hosts || echo "127.0.0.1 $h" >> /etc/hosts
done

echo "4/4 starting the transparent proxy on :443 ..."
pkill -f envoy-transparent.yaml 2>/dev/null || true
sleep 1
nohup "$ENVOY" -c "$CFG" --log-level warning > "$E/envoy443.log" 2>&1 &
sleep 3
if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9902/ready | grep -q 200; then
  echo "UP. Transparent interception active on :443."
else
  echo "WARN: :443 proxy admin not ready; check $E/envoy443.log"; tail -3 "$E/envoy443.log"; exit 1
fi

echo
echo "self-test (through the live :443 data plane):"
CA="$E/ca.crt"
deny=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" https://api.anthropic.com/v1/messages \
  -H 'content-type: application/json' -d '{"messages":[{"role":"user","content":"My card is 4111 1111 1111 1111"}]}')
allow=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 --cacert "$CA" https://api.anthropic.com/v1/messages \
  -H 'content-type: application/json' -d '{"messages":[{"role":"user","content":"hello there"}]}')
echo "  DENY  (valid card) -> HTTP $deny   (expect 403)"
echo "  ALLOW (benign)     -> HTTP $allow  (expect 401/400 from real Anthropic, NOT 403/504)"
echo
echo "Now run 'claude' normally (NO env vars needed) and send a test prompt."
echo "Watch captures:  curl -s http://127.0.0.1:8899/console/violations.json | python3 -m json.tool"
