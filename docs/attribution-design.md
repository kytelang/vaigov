# AI-system attribution

## The problem

Violations are captured at the Envoy edge from the actual network request. A raw
packet does not carry any "which registered AI system made this call" identity,
so attribution needs an explicit identity signal. Without one, every violation we
show in the console is real but anonymous: we know a policy was breached, not
which of the operator's registered systems breached it.

This note records how varman attributes a captured violation to a system, what is
implemented today, and what remains. It is deliberately honest about the fact
that attribution cannot be invented from packet contents: an untagged call from
an unmapped caller stays unattributed, and the console reports it that way rather
than guessing.

## The identity signals (priority order)

1. **Explicit egress tag (`x-varman-system`)** — the reliable, first-class
   signal, and the only one needed for attribution to work. An operator
   registers a system in the console, gets its id, and configures that system's
   egress (its own sidecar/proxy, or the app itself) to stamp
   `x-varman-system: <id>` on outbound calls. This is a declaration of identity
   by the system, carried on the request varman already sees.

2. **Published principal -> system map** — the enrichment path for callers that
   cannot be changed to tag their own traffic but whose authenticated principal
   (mTLS SPIFFE id, service account, API-key subject) is known. The operator maps
   principals to systems in the console; the control plane serves that mapping,
   signed; the sidecar pulls it the same way it pulls policy packs and content
   rules, and resolves the principal at capture time.

3. **Unattributed** — no tag and no principal mapping. The violation is recorded
   honestly with `system_id = ""` and reported as unattributed.

## What is implemented (sidecar, build-green + tested)

- `violation.Violation.systemId` — the attributed system id, defaulting to "".
- `violation.canonicalDoc` includes `system_id`, so attribution is part of the
  **signed core**: once a violation is attributed, that attribution cannot be
  altered without breaking the Ed25519 signature (tamper-evident end to end).
  `toJson`/`fromJson` carry it losslessly, so a reloaded record still verifies.
- `violation.parseDecision` reads `input.system_id` / `input.system` from the
  OPA decision input (the routing-level relay path).
- `sysresolve.ky` — the resolver: `resolve(explicitTag, principal, SystemMap)`
  (tag wins, else principal lookup, else ""), a `SystemMap` class, and
  `loadJson(raw)` for the pulled signed map document.
- `state.SidecarState.sysMap` + `setSystemMap(raw)` — holds the pulled map; the
  content-firewall check (`cfcheck.ky`) stamps the resolved id onto every
  violation it records.
- `tests/sidecar_test.ky::test_attribution_resolve_and_signed_core` — verifies
  the resolve priority, the signed round-trip, and that tampering with the
  attribution breaks verification. The whole sidecar suite is green (13/13).

With the explicit tag alone, attribution is functional with no control-plane
state at all: a tagged request produces an attributed, signed violation today.

## What remains (control plane, untestable locally)

These need a live Entra/multi-tenant control plane and the shared `acp` Postgres
schema, so they are listed as the remaining wire-up rather than built blind:

- **Signed map-serve endpoint** — the control plane serves the operator's
  principal -> system map, Ed25519-signed, for the sidecar to pull. Mirror the
  content-rules `ActiveSet` edge-pull.
- **Sidecar pull** — `sync.ky` fetches that map, verifies the signature, and
  calls `state.setSystemMap`. (The install path already exists.)
- **Display** — surface `system_id` on the decisions/violations view and an
  attributed-violations count on the Systems detail screen. The shared
  `decisions` table has no `system_id` column and the server's `runMigrations`
  is a stub, so this needs either an applied migration or reading the id back out
  of the decision `input_json` that already round-trips through ingest.

## Why "HR" in AI Systems can connect to a violation

Registering a system ("HR copilot") gives it an id. The moment that system's
egress tags its calls with `x-varman-system: hr-copilot` (or its principal is
mapped), every violation it triggers is attributed to it, signed, and
countable against it in the console. Until one of those two signals is present,
the system is a catalogue entry and its violations are unattributed, which is the
honest state and exactly what the console shows.
