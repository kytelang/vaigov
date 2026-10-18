#!/usr/bin/env bash
# Launch the varman control plane with Entra sign-in configured. Reads the
# (gitignored) .entra.env for the app-registration secrets, then execs the built
# server. Usage: ./serve.sh   (or: nohup ./serve.sh > server.out 2>&1 &)
set -euo pipefail
cd "$(dirname "$0")"
if [ -f .entra.env ]; then set -a; . ./.entra.env; set +a; fi
exec ./varman-server.run "$@"
