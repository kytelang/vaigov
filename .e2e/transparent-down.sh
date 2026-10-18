#!/usr/bin/env bash
# Undo transparent interception. Run with sudo:
#   sudo bash /Users/kamlesh/kytelang/varman/.e2e/transparent-down.sh
set -e
E=/Users/kamlesh/kytelang/varman/.e2e
if [ "$(id -u)" != "0" ]; then echo "run with sudo"; exit 1; fi

echo "stopping :443 proxy ..."; pkill -f envoy-transparent.yaml 2>/dev/null || true
echo "removing /etc/hosts redirects ..."
sed -i '' '/^127\.0\.0\.1 api\.anthropic\.com$/d;/^127\.0\.0\.1 api\.openai\.com$/d;/^127\.0\.0\.1 generativelanguage\.googleapis\.com$/d' /etc/hosts
echo "untrusting the demo CA ..."; security delete-certificate -c "Varman Demo CA" /Library/Keychains/System.keychain 2>/dev/null || true
echo "DONE. System restored; your clients talk to the real providers again."
