# Varman deployment guide: container app, sidecar, Envoy and OPA

This guide describes how to run Varman as a set of containers: the control plane
as a container app, the Varman sidecar alongside it, and the data plane made of
Envoy plus the OPA Envoy plugin. It is written for an operator who is deploying
Varman into an organisation's environment for the first time, for example a
shadow-mode pilot (see `pilot-readiness-plan.md` and `security/shadow-mode-sow.md`).

Everything here is grounded in the actual components in this repository. The
reference Envoy configuration lives in `.e2e/envoy.yaml` (demo) and
`.e2e/envoy-transparent.yaml` (transparent :443 interception); the control plane
reads `server/app.yaml`; the sidecar reads a flat YAML described in
`sidecar/src/settings.ky`; and the control plane even hands you a ready-to-edit
OPA sidecar config at `GET /integration`.

## 1. What you are deploying

Varman has two planes. Keep them separate in your head, because they enforce two
different things.

**The control plane** is the Varman server (`server/`). It is an ordinary Kyte
web app backed by PostgreSQL. It does three jobs:

- serves the operator console (a hypermedia UI) over HTTPS,
- serves machine endpoints the data plane pulls from:
  - `GET /v1/bundles/{name}` returns the gzip-tar OPA policy bundle
    (`policy.rego` plus a `.manifest`), compiled from the tenant's rules,
  - `GET /integration` returns a ready-to-edit OPA sidecar config plus the live
    revision,
  - `GET /content-rules` returns the signed content-firewall rule set (with
    `x-acp-pubkey` and `x-acp-signature` headers),
  - `GET /ai-endpoints` returns the governed AI endpoint registry,
  - `POST /logs` and `POST /violations` receive decision logs and violation
    evidence,
- authenticates operators with Microsoft Entra (OIDC).

**The data plane** sits in the egress path of your AI traffic and enforces two
things on every request:

1. **Tool-call / request authorisation** via OPA. Envoy's `ext_authz` filter
   asks OPA for an allow or deny decision. OPA runs the policy bundle it pulls
   from the control plane, and ships decision logs back. This is the
   `opa-envoy-plugin` path.
2. **Content inspection** (the content firewall) via the Varman sidecar. Envoy
   calls the sidecar's `POST /cf/check` with the request body; a `200` means
   allow, a `403` means deny. The sidecar pulls the signed content rules from
   the control plane, serves the last-good set when the control plane is down,
   and records every violation as a signed, verifiable record.

```
          operators (browser)
                 |
                 | HTTPS + Entra sign-in
                 v
        +------------------+        PostgreSQL
        |  Control plane   |<------->  (store)
        |  (server, :8080) |
        +------------------+
          ^            ^
   bundle |            | signed content rules,
  + logs  |            | endpoints, violations
          |            |
+---------+--+     +---+---------------+
|  OPA        |     |  Varman sidecar   |
| (:9191,     |     |  (:8899, /cf/check|
| opa-envoy-  |     |   + /policy/bundle)|
| plugin)     |     +---+---------------+
+------+------+         ^
       | ext_authz      | Lua httpCall /cf/check
       | (gRPC/HTTP)    |
       v                |
   +--------------------+-------------------+
   |              Envoy (data plane)        |   <- AI-bound egress traffic
   |  :10000 (demo) or :443 (transparent)   |      flows through here
   +----------------------------------------+
                 |
                 v
     api.anthropic.com / api.openai.com / generativelanguage.googleapis.com / ...
```

### Ports at a glance

| Component | Port | Purpose |
|---|---|---|
| Control plane (server) | `8080` | HTTPS console + machine endpoints (set by `config.port` in `app.yaml`, overridable with `--port`) |
| PostgreSQL | `5432` | Control-plane store |
| Varman sidecar | `8899` | Neutral HTTP contract: `/healthz`, `/policy/bundle`, `/policy/rego`, `/ai-endpoints`, `/cf/check`, `/violations`, `/logs` (set by `listen`) |
| OPA (opa-envoy-plugin) | `9191` | `ext_authz` endpoint Envoy calls (set by `opa_addr`) |
| Envoy | `10000` | Demo ingress listener (`.e2e/envoy.yaml`) |
| Envoy | `443` | Transparent interception listener (`.e2e/envoy-transparent.yaml`) |
| Envoy admin | `9901` / `9902` | Stats and config dump |

## 2. Prerequisites

- Docker 24+ (or Podman) and Docker Compose v2, or a Kubernetes cluster.
- A PostgreSQL 14+ instance the control plane can reach. The schema is applied by
  the server itself in `--migrate` mode, so you only need an empty database and a
  role that can create tables.
- A Microsoft Entra app registration for operator sign-in (tenant id, client id,
  client secret, and a redirect URI that matches your public HTTPS URL). See
  `docs/entra.md`.
- A TLS certificate and key for the control plane's public hostname. A pilot can
  start with a self-signed cert, but Entra requires an HTTPS redirect URI, so
  plan for a CA-issued cert for anything beyond a single machine.
- The Kyte toolchain to build the two binaries (`kyte build`). Builds run on
  Linux or macOS/WSL2; the resulting binary is a static native executable you
  copy into a slim runtime image. (Native `zig build` does not work on a bare
  Windows host; build in WSL2 or a Linux container.)
- A demo CA and per-host leaf certificates if you want Envoy to terminate TLS for
  the governed providers (TLS bump). The reference set lives in `.e2e/` for the
  demo; a real deployment mints its own CA and distributes it to clients.

## 3. Build the container images

Both the control plane and the sidecar are Kyte web apps. Build the native
binary on a builder stage, then copy it into a minimal runtime image. The
pattern below is the same for both; only the project directory and the binary
name differ.

### 3.1 Control plane image

The server project builds to `build/debug/bin/server` (or build it release). It
needs its `wwwroot/`, `app.yaml`, `certs/`, and the compiled Postgres driver at
runtime.

`server/Dockerfile`:

```dockerfile
# ---- build stage ----
FROM kytelang/kyte-toolchain:latest AS build
WORKDIR /src
COPY packages/ /src/packages/
COPY server/ /src/server/
WORKDIR /src/server
# project.json pulls kyte-datastar and kyte-postgres; kyte build fetches them.
RUN kyte build

# ---- runtime stage ----
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/server/build/debug/bin/server /app/server
COPY --from=build /src/server/wwwroot /app/wwwroot
COPY --from=build /src/server/app.yaml /app/app.yaml
# Certs are mounted at runtime (see compose), not baked into the image.
EXPOSE 8080
# ENTRA_CLIENT_SECRET is injected at runtime; never bake it in.
ENTRYPOINT ["/app/server"]
CMD ["--port", "8080"]
```

> Build the trust packages into the image: the server imports `varman-core` from
> `packages/`, resolved by Kyte's local package scan, so copy `packages/` into
> the build context (as above) and build from the component directory.

### 3.2 Sidecar image

The sidecar project builds to `build/debug/bin/varman-sidecar`. It is
self-contained; it only needs its config file and writable paths for its caches
and the signed violation store.

`sidecar/Dockerfile`:

```dockerfile
FROM kytelang/kyte-toolchain:latest AS build
WORKDIR /src
COPY packages/ /src/packages/
COPY sidecar/ /src/sidecar/
WORKDIR /src/sidecar
RUN kyte build

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/sidecar/build/debug/bin/varman-sidecar /app/varman-sidecar
EXPOSE 8899
VOLUME ["/data"]
ENTRYPOINT ["/app/varman-sidecar"]
CMD ["--config", "/app/varman-sidecar.yaml"]
```

## 4. Configure the control plane

The control plane reads a single `config:` subtree from `app.yaml` (never
environment variables, which collide when apps share a host). Mount your own
`app.yaml`; do not edit the one baked into the image.

`app.yaml` (production shape, based on `server/app.yaml`):

```yaml
config:
  port: 8080

  db:
    dsn: "postgres://varman@db:5432/varman"
    poolSize: 8

  # TLS 1.3 termination. Point these at your CA-issued cert and key (mount them
  # read-only; keep the key out of the image and out of version control).
  tls:
    enabled: true
    certPath: "/certs/tls.crt"
    keyPath: "/certs/tls.key"

  # Microsoft Entra interactive sign-in. Leave clientSecret EMPTY here; the
  # server reads it from the ENTRA_CLIENT_SECRET environment variable at runtime.
  entra:
    tenantId: "<your-tenant-id>"
    clientId: "<your-client-id>"
    clientSecret: ""
    redirectUri: "https://varman.example.org/auth/callback"
```

Key points:

- **The client secret never goes in `app.yaml`.** Inject it as the
  `ENTRA_CLIENT_SECRET` environment variable (the server reads it via
  `entraSecret`). In Compose use an `env_file`; in Kubernetes use a `Secret`.
- **The redirect URI must match the public HTTPS URL exactly** and must be
  registered on the Entra app. For a pilot that is reachable at
  `https://varman.example.org`, the redirect URI is
  `https://varman.example.org/auth/callback`.
- **Multi-org SaaS**: make the Entra app multitenant and set
  `tenantId: organizations`. For a single-workspace deploy, use the home tenant id.
- **Trust keys**: for a real deployment set the trust `seedHex` and
  `sessionKeyHex` (the server refuses to start in production without them and
  tells you so). `--dev-auth` fills working local keys and must only be used in
  development.

### 4.1 Apply the schema (migration gate)

Run the server once in `--migrate` mode against your database before serving
traffic. It applies the schema and exits; it never serves in this mode.

```sh
docker run --rm \
  -v $PWD/app.yaml:/app/app.yaml:ro \
  --env-file ./entra.env \
  varman-server --migrate
```

The orchestrator can run this automatically as a pre-rollout gate: uncomment the
`migrate:` block in `app.yaml` and new replicas only roll out if the one-shot
exits `0`.

## 5. Configure the sidecar

The sidecar reads a **flat** top-level YAML (not a `config:` subtree). Every key
has a built-in default (see `sidecar/src/settings.ky`), so you only set what you
need to change.

`varman-sidecar.yaml`:

```yaml
# Where the control plane lives, and which tenant this sidecar serves.
control_plane: "https://varman.example.org"
tenant: "default"
token: ""                       # optional bearer presented to the control plane

# The neutral HTTP contract Envoy and OPA talk to.
listen: "0.0.0.0:8899"

# OPA bundle name and how often to poll the control plane.
bundle_name: "policy"
poll_secs: 30
flush_secs: 10

# Content firewall master switch and its last-good cache.
content_firewall: true
cf_rules_cache: "/data/content-rules.json"

# Durable, signed violation store (source of truth) + its SQLite search index
# is derived automatically at vstore_path + ".idx.db".
vstore_path: "/data/violations"
vcursor_path: "/data/violations.cursor"

# Verify everything pulled from the control plane against its public key. Read
# the value from the x-acp-pubkey header on GET /content-rules once, then pin it.
cp_pubkey: "<control-plane-ed25519-pubkey-hex>"

# Provision a real Ed25519 signing seed (64 hex). If empty, a dev key is used and
# the sidecar logs a warning; never ship a pilot on the dev key.
signing_seed: "<64-hex-ed25519-seed>"

# Store a redacted preview + hash instead of the full prompt (privacy-preserving).
prompt_redact: true

# Optional: where to write the generated Envoy config + per-host certs. Leave
# empty if you manage Envoy config yourself (recommended for containers).
envoy_dir: ""
ca_dir: "/certs"

# Optional: ticketing integration for auto-raising on deny/step_up.
ticketing_url: ""
ticketing_system: "generic"
ticket_on: "deny"
```

Operational notes:

- **Pin `cp_pubkey`.** With it set, the sidecar refuses config it cannot verify
  against the control plane's Ed25519 public key. Leaving it empty skips the
  check; do not do that outside development.
- **Set a real `signing_seed`.** The violation evidence chain is only meaningful
  if the signing key is provisioned and kept secret. The sidecar self-checks the
  whole chain at boot and warns loudly if it is broken.
- **Give `/data` a persistent, single-writer volume.** The signed log is the
  source of truth; a second concurrent writer on the same file corrupts the
  chain. One sidecar instance per volume.
- **Resilience.** The sidecar serves the last-good bundle, endpoint registry,
  and content rules from disk even if the control plane is down at boot, so the
  data plane keeps enforcing during a control-plane outage.

## 6. Configure OPA (the opa-envoy-plugin)

OPA runs as its own container using the **opa-envoy-plugin** build of OPA (the
`openpolicyagent/opa:<version>-envoy` image), which adds the Envoy external
authorization gRPC service on top of standard OPA.

OPA pulls the policy bundle and ships decision logs. The control plane generates
this config for you: `GET /integration` returns a ready-to-edit block. It looks
like this (from the live handler), with `CONTROL_PLANE_URL` filled in:

`opa-config.yaml`:

```yaml
services:
  varman:
    url: https://varman.example.org
    headers:
      x-acp-tenant: "default"

bundles:
  acp:
    service: varman
    resource: /v1/bundles/policy
    polling:
      min_delay_seconds: 20
      max_delay_seconds: 60

decision_logs:
  service: varman
  reporting:
    min_delay_seconds: 5
    max_delay_seconds: 15

# Envoy external authorization plugin: the gRPC service Envoy's ext_authz calls.
plugins:
  envoy_ext_authz_grpc:
    addr: ":9191"
    path: acp/allow
    dry-run: false
```

Notes:

- **Bundle resource.** `resource: /v1/bundles/policy` maps to the control
  plane's `GET /v1/bundles/{name}` with `name = policy`. OPA re-pulls on the
  polling schedule and activates each new revision atomically.
- **Decision logs** are posted back to the control plane (`/logs`), giving you an
  auditable record of every allow/deny.
- **Resilience variant.** To survive control-plane outages you can point OPA's
  `services.varman.url` at the sidecar instead (the sidecar serves the last-good
  bundle at `GET /policy/bundle` and caches it on disk). In that case set the URL
  to the sidecar's address and keep the same `resource` path semantics.
- **`dry-run: true`** makes OPA log what it would have denied without denying it.
  Use this for the shadow-mode phase of a pilot, then flip it to `false` to
  enforce.
- **`path: acp/allow`** is the Rego decision entrypoint. The compiled bundle
  defines `package acp` with an `allow` rule and a default of `allow` when no
  rule matches (matching the control plane's fall-through), so the policy fails
  open to the configured default until you author deny rules.

## 7. Configure Envoy (the data plane)

Envoy terminates TLS for the governed providers (TLS bump), runs the two checks,
and forwards allowed traffic upstream. Start from `.e2e/envoy.yaml` (a per-host
demo) or `.e2e/envoy-transparent.yaml` (transparent :443). The reference configs
wire the **content check** via a Lua `httpCall` to the sidecar's `/cf/check`. To
add the **OPA authorisation check**, insert an `ext_authz` filter before the Lua
filter in each filter chain.

The `http_filters` list for a governed host becomes (filters run top to bottom):

```yaml
http_filters:
# 1. Tool-call / request authorisation: ask OPA. Deny short-circuits here.
- name: envoy.filters.http.ext_authz
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
    transport_api_version: V3
    grpc_service:
      envoy_grpc:
        cluster_name: opa
      timeout: 1s
    # Fail closed: if OPA is unreachable, deny rather than allow.
    failure_mode_allow: false

# 2. Content firewall: POST the body to the sidecar's /cf/check.
- name: envoy.filters.http.lua
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
    default_source_code:
      inline_string: |
        function envoy_on_request(handle)
          local body = handle:body(true)
          local b = ""
          if body ~= nil and body:length() > 0 then b = body:getBytes(0, body:length()) end
          local h, _ = handle:httpCall("content",
            { [":method"]="POST", [":path"]="/cf/check", [":authority"]="sidecar", ["content-type"]="text/plain" },
            b, 5000)
          if h == nil or h[":status"] ~= "200" then
            handle:respond({ [":status"]="403", ["content-type"]="text/plain", ["x-acp-content-verdict"]="deny" },
              "blocked by content policy\n")
          end
        end

# 3. Route to the upstream provider.
- name: envoy.filters.http.router
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```

Add the matching clusters (the `content` cluster already exists in the reference
config; add an `opa` cluster for ext_authz):

```yaml
clusters:
- name: content          # the Varman sidecar
  connect_timeout: 2s
  type: STRICT_DNS
  load_assignment:
    cluster_name: content
    endpoints:
    - lb_endpoints:
      - endpoint: { address: { socket_address: { address: sidecar, port_value: 8899 } } }

- name: opa              # OPA ext_authz gRPC
  connect_timeout: 1s
  type: STRICT_DNS
  typed_extension_protocol_options:
    envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
      "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
      explicit_http_config: { http2_protocol_options: {} }
  load_assignment:
    cluster_name: opa
    endpoints:
    - lb_endpoints:
      - endpoint: { address: { socket_address: { address: opa, port_value: 9191 } } }
```

The upstream provider clusters (`anthropic`, `openai`, `gemini`, plus any you add
through the console's governed-endpoints screen) and the per-host TLS filter
chains are exactly as in `.e2e/envoy.yaml`; copy them as-is and change only the
certificate paths and upstream addresses for your environment.

> **Ordering matters.** Put `ext_authz` before the Lua filter so an OPA deny
> short-circuits before the body is inspected. Set `failure_mode_allow: false`
> so an OPA outage fails closed. The Lua filter already fails closed (a non-200
> or a missing sidecar response becomes a 403).

## 8. Put it together with Docker Compose

`docker-compose.yaml`:

```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: varman
      POSTGRES_DB: varman
      POSTGRES_HOST_AUTH_METHOD: trust   # pilot only; use a password in production
    volumes: ["pgdata:/var/lib/postgresql/data"]

  migrate:
    image: varman-server
    command: ["--migrate"]
    env_file: ./entra.env
    volumes:
      - ./app.yaml:/app/app.yaml:ro
      - ./certs:/certs:ro
    depends_on: [db]
    restart: "no"

  server:
    image: varman-server
    command: ["--port", "8080"]
    env_file: ./entra.env          # ENTRA_CLIENT_SECRET lives here
    ports: ["8080:8080"]
    volumes:
      - ./app.yaml:/app/app.yaml:ro
      - ./certs:/certs:ro
    depends_on: [db, migrate]

  sidecar:
    image: varman-sidecar
    command: ["--config", "/app/varman-sidecar.yaml"]
    volumes:
      - ./varman-sidecar.yaml:/app/varman-sidecar.yaml:ro
      - ./certs:/certs:ro
      - sidecardata:/data
    depends_on: [server]

  opa:
    image: openpolicyagent/opa:latest-envoy
    command:
      - "run"
      - "--server"
      - "--config-file=/config/opa-config.yaml"
      - "--addr=0.0.0.0:8181"
      - "--diagnostic-addr=0.0.0.0:8282"
    volumes:
      - ./opa-config.yaml:/config/opa-config.yaml:ro
    depends_on: [server]

  envoy:
    image: envoyproxy/envoy:v1.31-latest
    command: ["-c", "/etc/envoy/envoy.yaml"]
    ports:
      - "10000:10000"   # ingress (demo) ; use 443:443 for the transparent config
      - "9901:9901"     # admin
    volumes:
      - ./envoy.yaml:/etc/envoy/envoy.yaml:ro
      - ./certs:/certs:ro
    depends_on: [sidecar, opa]

volumes:
  pgdata:
  sidecardata:
```

`entra.env` (gitignored):

```
ENTRA_CLIENT_SECRET=<the app-registration secret>
```

Bring it up:

```sh
docker compose up -d db
docker compose run --rm migrate      # one-shot schema apply
docker compose up -d server sidecar opa envoy
```

## 9. Kubernetes sketch

The same five workloads map cleanly onto Kubernetes. The usual shape:

- **control plane**: a `Deployment` + `Service`, `app.yaml` from a `ConfigMap`,
  TLS cert and `ENTRA_CLIENT_SECRET` from `Secret`s, and an `Ingress`/Gateway
  terminating the public HTTPS hostname. Run the migration as a `Job` (or an
  init container) that must succeed before the Deployment rolls out.
- **sidecar + OPA + Envoy** are the per-workload data plane. Deploy them as
  sidecar containers in the pods whose egress you govern (so the content check
  and OPA are a localhost hop away), or as a shared egress gateway Deployment.
  The sidecar's `/data` must be a `PersistentVolumeClaim` with a single writer
  (one replica per volume), because the signed violation log is append-only and
  single-writer.
- **PostgreSQL**: a managed instance or an in-cluster `StatefulSet`.

Keep the Envoy `ext_authz` cluster pointing at the OPA container in the same pod
(`127.0.0.1:9191`) and the `content` cluster at the sidecar
(`127.0.0.1:8899`) when co-located, which is the lowest-latency and most
failure-isolated layout.

## 10. Verify the deployment

Once everything is up, walk the path end to end. `scripts/cf-local-test.sh` does
exactly this against a throwaway database and is the canonical reference; the
manual checks below mirror it.

1. **Control plane is healthy and serving over TLS:**
   ```sh
   curl -sk https://varman.example.org/healthz
   ```
2. **The OPA bundle compiles and is served:**
   ```sh
   curl -sk https://varman.example.org/v1/bundles/policy -H 'x-acp-tenant: default' -o bundle.tar.gz
   tar tzf bundle.tar.gz    # expect policy.rego and a .manifest
   ```
3. **OPA pulled and activated the bundle:**
   ```sh
   curl -s http://localhost:8282/health?bundle=true    # OPA diagnostic addr
   ```
4. **The signed content rule set is served and signed:**
   ```sh
   curl -skD - -o /dev/null https://varman.example.org/content-rules -H 'x-acp-tenant: default' \
     | grep -i 'x-acp-signature\|x-acp-pubkey'
   ```
5. **The sidecar pulled, verified and compiled the rules:** check the sidecar log
   for `content rules updated`, and:
   ```sh
   curl -s http://localhost:8899/healthz
   ```
6. **Enforcement decisions are correct** (what Envoy's checks receive):
   ```sh
   # content firewall directly:
   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:8899/cf/check \
     --data-binary 'summarise the quarterly report'          # expect 200 (allow)
   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:8899/cf/check \
     --data-binary 'my token is sk-ABCDEF1234567890'         # expect 403 (deny)
   ```
7. **A real request through Envoy is governed end to end:** send a governed
   provider request through the Envoy listener and confirm a benign prompt
   succeeds and a policy-violating one is blocked with `403` and
   `x-acp-content-verdict: deny`.
8. **Evidence is recorded and verifiable:**
   ```sh
   curl -s http://localhost:8899/console/violations.json | python3 -c \
     'import sys,json;d=json.load(sys.stdin);print(d["total"],"records,",sum(v["verified"] for v in d["violations"]),"verified")'
   ```

## 11. Operations and hardening

- **Secrets.** `ENTRA_CLIENT_SECRET`, the TLS private key, the trust `seedHex`
  and `sessionKeyHex`, and the sidecar `signing_seed` are all secrets. Mount them
  from your secret store; never bake them into images or commit them.
- **TLS.** Use a CA-issued cert for the control plane. For the data plane's TLS
  bump, mint a dedicated CA, keep its key offline, and distribute only the CA
  certificate to the clients whose traffic you inspect. Document this in your
  data-flow and threat-model packet (`docs/security/`).
- **Shadow mode first.** Start OPA with `dry-run: true` and content rules in
  `shadow` action so the pilot observes and records without blocking, then flip
  to enforce once the decision log looks clean. This is the shadow-mode pilot
  described in `docs/security/shadow-mode-sow.md`.
- **Fail closed.** Keep `failure_mode_allow: false` on `ext_authz`. The sidecar's
  content check already fails closed. The trade-off is that a data-plane
  dependency outage blocks governed traffic; size and monitor OPA and the sidecar
  accordingly.
- **Single-writer evidence.** One sidecar per violation-store volume. The chain
  self-check at boot tells you if a second writer or tampering broke it.
- **Resilience.** Both the sidecar (bundle, endpoints, content rules) and OPA
  (last-good bundle) keep enforcing while the control plane is down. The control
  plane is on the authoring and audit path, not the per-request hot path.
- **Backups.** Back up PostgreSQL (the control-plane store) and each sidecar's
  `/data` volume (the signed evidence log).

## 12. Reference files

| File | What it is |
|---|---|
| `server/app.yaml` | Control-plane config template (`config:` subtree) |
| `sidecar/src/settings.ky` | The authoritative list of sidecar config keys and defaults |
| `.e2e/envoy.yaml` | Reference Envoy config, per-host TLS bump + content check |
| `.e2e/envoy-transparent.yaml` | Reference Envoy config, transparent :443 interception |
| `GET /integration` (live) | Control plane hands you the OPA sidecar config + live revision |
| `scripts/cf-local-test.sh` | Canonical end-to-end verification script |
| `docs/pilot-readiness-plan.md` | What a pilot needs before production |
| `docs/security/` | Data-flow, threat model, questionnaire, shadow-mode SOW |
| `docs/entra.md` | Entra app-registration setup |
