# 8. Identity, registry and access

Authorization is only as good as the identity behind it. Varman verifies two identities: the
**agent** making the call, and the **human principal** it acts for. Neither is taken from the agent's
own claims.

## Agent identity: the registry

The control plane is the source of truth for applications and agents, stored in the control-plane
database. Register them from the console (Teams and Agents pages) or the control-plane API; each agent
registration issues a one-time token and the store keeps only its SHA-256.

```sh
# from the console: Teams -> Register team, then Agents -> Register agent
# or the API:
curl -X POST http://<host>:8787/apps   -d '{"name":"acme-app","owner":"you"}'
curl -X POST http://<host>:8787/agents -d '{"app_id":"<app-id>","name":"coding-assistant"}'
# the agent response carries a one-time token, shown once
```

Register agents from the console (Teams and Agents pages) or the control-plane API; they are stored
in the control-plane database. At enforcement time the proxy verifies the agent against that database
by pointing `--registry-url` at the control plane (a local registry file via `--registry` is the
offline alternative). Verification is fail-closed: a wrong or revoked token yields no identity, and
the call is denied. Deactivating an agent in the console refuses it immediately, verified end to end.

### How to register a team (step by step)

1. Open the console and select **Teams** in the sidebar.
2. Click **+ Register team** (top right of the Teams and agents card). The **Register a team / application** popup opens.
3. Fill in **Name** (required, for example `acme-app`) and, optionally, **Owner**.
4. Click **Register**. The team appears in the list with its generated id (`app-...`), which you will need when registering agents.

### How to register an agent (step by step)

1. Select **Agents** in the sidebar.
2. Click **+ Register agent**. The **Register an agent** popup opens.
3. Fill in **App ID** (required, the `app-...` id from the team you just registered) and **Name** (required, for example `coding-assistant`).
4. Click **Register**. The result line shows a **one-time token**. Copy it now: it is shown once and only its SHA-256 is stored. The agent presents this token at enforcement time, and the proxy verifies it against the control-plane database.

To revoke an agent, use its **Deactivate** action on the Agents page; enforcement refuses it immediately.

## Per-agent virtual keys: authenticated identity

The one-time token an agent registration issues is that agent's **virtual key**. A caller presents it so
the enforcement point knows *which* agent is acting, without trusting a header the agent could spoof.

At the LLM gateway (and the MCP proxy), the caller sends the token in the `x-acp-agent-key` header. The
enforcement point resolves it against the control plane, which hashes the key and looks up the agent:

```sh
# the enforcement point resolves a presented virtual key (this is what the gateway does for you)
curl -X POST http://<host>:8787/agents/resolve-key -d '{"key":"<the-agents-token>"}'
# -> {"ok":true,"verified":true,"agent_id":"agt-...","name":"coding-assistant","app_id":"app-...","tenant":"..."}
```

The store keeps only the SHA-256 of the token, so the plaintext key is never persisted. A resolved key
gives a **verified** identity, and the policy can rely on the `agent:` and `app:` subject with
confidence. The legacy `x-acp-app` header still works as a fallback, but it is marked **unverified**, so
a policy can deny or step up an unattributed high-risk call. On the enforcement path, `POST /agents/verify`
with `{id, token}` is the equivalent check when the caller already holds both the id and the token.

## Human identity: OIDC and Entra

The human principal is established from a verified OIDC/JWT bearer token. Varman verifies EdDSA and
real RS256 signatures, resolves the key by `kid` from a JWKS it fetches and refreshes, and checks the
issuer, audience and expiry. Configure Entra on the PEP or the control plane; the generic OIDC flags
are accepted by the control plane:

```sh
# Microsoft Entra
--entra-tenant <tenant> --entra-audience <audience>
# any OIDC provider (control plane)
--oidc-jwks <url> --oidc-issuer <iss> --oidc-audience <aud>
```

A request without a valid token degrades to the `unattributed` principal, which your policy can
treat as it wishes (for example, denying `unattributed` access to secrets or frontier models). For
local development, `--dev-auth` on the control plane issues mock tokens and enables the dev-login and
dev-token routes; without that explicit flag those routes are absent and the server refuses to start
with no signing seed and no session key, so it cannot be switched on by accident.

::: warning Varman: the interactive OIDC login callback is not fully verified yet
The PEP bearer-token path verifies the presented token's signature against the configured key set,
issuer, audience and expiry. The **interactive human-login callback** (the browser OIDC flow) does
**not** yet verify the id_token signature against the IdP JWKS and does not bind the login nonce, so the
CSRF `state` check is in place but id_token authenticity and replay protection are not. Do not rely on
the browser login path for a hard identity guarantee until this is closed.
:::

### Preflighting a real tenant

Before cutting over to a real Entra tenant, verify the setup without starting the server:

```sh
# fetch and parse the tenant's JWKS (no token needed)
acp-server --entra-preflight --entra-tenant <tenant> --entra-audience <audience>
# with a real token: verify iss/aud/nbf/exp/signature and print the roles and effective capabilities
acp-server --entra-preflight --entra-tenant <tenant> --entra-audience <audience> --entra-test-token "<JWT>"
```

It exits 0 on success and 1 on any failure, naming the exact check that failed. The full cutover
procedure (JWKS preflight, token preflight, bring-up, first-window soak covering key rotation, clock
skew, token expiry and SCIM group sync, and rollback) is in `docs/entra-cutover-runbook.md`.

## Delegation

A `Delegation` binds an agent to a human for a bounded time, so the ledger records not just "agent X
did this" but "agent X, acting for human Y, did this". This is what lets you answer "who authorised
this action" with a name, not just a service identity.

## Role-based access control

The control plane enforces RBAC with capabilities mapped from OIDC app roles:

| Role | Capability | What it can do |
| --- | --- | --- |
| `PolicyAdmin` | `EditPolicy` | deploy a new policy version |
| `AppRegistrar` | `RegisterApp`, `RegisterAgent` | register applications and their agents; verify or deactivate an agent |
| `GrcAuthor` | `EditGrc` | create and advance governance records (assessments, conformity, risk, ...) |
| `FirewallAdmin` | `EditFirewall` | change the central content-firewall config and rules |
| `Approver` | `Approve` | resolve a step-up hold |
| `BreakGlassOperator` | `BreakGlass` | engage or clear the kill-switch |
| `Auditor` | `Export` | export the evidence and violation ledger |
| `SecurityOfficer` | `SeeArgs` | read the raw decision detail |

**Separation of duty** follows from this role-to-capability mapping: registration, policy authoring,
GRC authoring, firewall changes, approvals, export, argument visibility and break-glass are each a
distinct capability held by a distinct role. A `PolicyAdmin` alone cannot trip the kill-switch, onboard
an application, author a governance record or export evidence. Grant the roles to different people to
keep the duties separate.

**Enforced today at every mutating route**, each on its own capability: policy deploy (`EditPolicy`);
apps (`RegisterApp`); agents register/verify/deactivate (`RegisterAgent`); GRC create/assess/status/
assign/control (`EditGrc`); firewall config and rules (`EditFirewall`); approvals (`Approve`); the
kill-switch (`BreakGlass`); the meta-audit write (`EditPolicy`). `Export` gates the CSV export of the
violation ledger, and `SeeArgs` gates the raw decision-detail read. When auth is on, each call needs a
bearer token carrying the matching capability, so a token for the wrong role is rejected with 403.
The control plane is fail-closed by default: it refuses to start in a non-dev configuration with no
signing seed and no session key, and RBAC-off local operation requires the explicit `--dev-auth` flag.
If you request real auth and the JWKS fails to load, the server likewise refuses to start rather than
run unprotected.

**SCIM 2.0 provisioning.** An IdP (or an operator) can read the role catalogue and the user-to-role
directory over SCIM: `GET /scim/v2/Groups` lists the eight ACP roles as SCIM groups (each carrying the
capabilities it grants under `urn:acp:capabilities`), and `GET /scim/v2/Users` lists the provisioned
users with their group memberships. Both are gated on `Export` (a read-only administrative view). The
user directory comes from `--scim-users <file>` (a JSON array of `{id, email, groups}`), defaulting to
a demo directory (one operator per role) under the mocked-IdP dev setup.

## Multi-agent delegation chains

A `Delegation` binds one human to one agent. When an agent calls another agent on the human's behalf,
the whole chain (user to agent A to agent B) is authorised together, and rights can only narrow along
it: agent B can never exercise a scope that agent A did not hold. The full chain is recorded in the
ledger, so "who authorised this" is answerable across hops. `POST /delegation/verify` returns a chain's
effective scopes and whether it permits a given scope, and the proxy enforces it: a call carrying an
`_acp_delegation` chain that widens rights along a hop, or that does not permit the operation, is denied
at the PEP.

## Permission-aware retrieval

When an agent retrieves documents for RAG, ACP can enforce that it only receives documents the acting
human may see, so an assistant cannot become a way around document ACLs. `POST /retrieval/check` decides
per candidate document against the verified principal and their groups; an unattributed caller is
fail-closed. The proxy enforces this on the response path too: documents the acting principal may not
see are filtered out of a retrieval tool result before it reaches the model. Point the agent at the
document-ACL export with `acp-agent mcp --retrieval-source <file|url>` (a SharePoint/Confluence/Drive
export of `documents[].{acl,permissions,sharing}`).

## Multi-tenancy

The control plane is multi-tenant. Tenant-scoped records (GRC, apps, agents, models, vendors) and the
content-firewall config carry a `tenant_id`, and each tenant gets its own Ed25519 signing key derived
from the control-plane key seed, so one tenant's evidence cannot be signed or read as another's. The
tenant for a request is resolved from the `x-acp-tenant` header, else the principal's Entra tenant,
else `default`. `GET /tenants` lists the tenants that have data.

::: danger Varman: tenant isolation is not safe yet
Deriving the tenant from the `x-acp-tenant` header is a known cross-tenant isolation gap. On the order
of 114 handler sites read the tenant from that header rather than binding it to the verified session, so
an authenticated caller who sets `x-acp-tenant: <another-tenant>` can read or write that tenant's data
on those paths. The content-rule authoring routes have been moved to session-derived tenant, but the
rest have not. Do not treat varman as providing safe tenant isolation until the tenant is derived from
the verified session everywhere.
:::

In the console, a tenant selector in the top bar sends the chosen tenant as the `x-acp-tenant` header
on every request, so it applies to reads and writes alike and an operator can switch tenants in the
browser (the page reloads to re-scope its panels), with `default` as the initial tenant.

## Signed egress identity across a boundary

When a governed call leaves one trust boundary and arrives at another enforcement point (a second proxy,
or a partner's control plane), a header can be spoofed in transit. A **signed egress identity** carries
the acting agent and human principal as an Ed25519-signed token, so the receiver attributes the call
cryptographically rather than on trust. Mint one with the CLI:

```sh
acp egress-identity \
  --key <32-byte-hex-seed> \
  --agent <agent-id> \
  --principal <human-id> \
  --group finance --group oncall
# prints:
#   x-acp-identity: acp <signed-token>
#   # signer pubkey (pin on the proxy): --identity-pubkey <hex>
```

The caller attaches the `x-acp-identity` header to its outbound request. The receiving proxy is started
with `--identity-pubkey <hex>` so it verifies the signature against that pinned key and rejects a
tampered or unsigned identity. The token binds the agent, the principal and any directory groups, so the
downstream policy can match on the same subject and groups it would have used locally, with the identity
proven rather than asserted.

## mutual TLS between components

Components can require mutual TLS so only enrolled parties reach the control API:

```sh
acp-server --tls-ca ca.pem --tls-cert server.pem --tls-key server.key ...
```

The server then presents its certificate and requires a client certificate signed by the ACP CA; a
client with no certificate or a rogue one fails the handshake.
