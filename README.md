# Varman (Kyte)

Varman, the Agent Control Plane (ACP), ported from Rust to Kyte. Migration plan and
design: `docs/verman-design.md`.

This is a monorepo mirroring the Rust workspace (`acp/crates/*` + `console`). Each
component is its own Kyte project; they share the trust core as a local package.

```
packages/
  varman-core/     # acp-core: trust core — value types, canonical bytes, RFC 6962
                   # verifiable log, Ed25519 signing; later the policy engines,
                   # the control catalogue, and compliance. (type: library)
server/            # acp-server: control-plane HTTP service (type: web)
sidecar/           # acp-sidecar: edge bundle-sync + violation relay + Envoy config
cli/               # acp-cli: offline / CI toolset (`varman`)
redteam/           # acp-redteam: adversarial policy tester
console/           # the existing Vue SPA, served by the server (not a Kyte project)
docs/              # design + migration plan
```

Components depend on `varman-core` by bare module import (`import types;`, `import sign;`),
resolved through Kyte's local `packages/` scan (run build/test from the component dir, or
the repo root, so `packages/` is on the search path). Store: PostgreSQL. Crypto: pure Kyte
(Ed25519 is in the Kyte stdlib).

## Status
- `packages/varman-core` — trust-core slices 1-2 implemented and known-answer gated:
  hashing, Merkle, Ed25519 signing, value model, canonical bytes, in-memory signed-head
  ledger. Run its tests: `cd packages/varman-core && kyte test tests/trust_test.ky` and
  `kyte test tests/types_canonical_test.ky`.
- `server`, `sidecar`, `cli`, `redteam` — scaffolds that compile against varman-core;
  implementations land slice by slice per the design doc's phased roadmap.
