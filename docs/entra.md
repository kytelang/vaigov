# Microsoft Entra sign-in (DPO + primary contact)

Varman lets the organisation's **primary contact** and **DPO** (the two emails
captured at org creation) sign in with Microsoft Entra. Until the Entra app
registration is configured, the control plane stays in dev-auth mode and this is
inert, so nothing breaks locally.

## What was built

- `entra-client` gained the OIDC authorization-code methods: `authorizeUrl`,
  `exchangeCode` (confidential client, secret sent server-to-server over TLS),
  and `decodeIdClaims`.
- `GET /auth/login` starts the flow: 303 to Entra `/authorize` with a fresh,
  cookie-bound `state` (CSRF) and `nonce` (replay), scope `openid profile email`.
  Returns 503 when Entra is not configured.
- `GET /auth/callback` verifies the `state` cookie, exchanges the code, decodes
  the id_token, and admits **only** the org's `contact_email` or DPO email. Any
  other identity gets 403. On success it mints the same signed session cookie the
  dev-login path uses, so every capability check works identically.
- Roles granted: **primary contact → PolicyAdmin + GrcAuthor + FirewallAdmin +
  Approver** (org administrator); **DPO → GrcAuthor + Auditor** (governance +
  audit/export).
- `GET /auth/session` reports `login_available: true` once Entra is configured,
  so the console shows the Sign-in button.

## Azure portal setup (step by step)

Everything below is one app registration. The login (delegated) and the org
group mapping (app-only) both use it.

### 1. Register the application
Azure portal -> Microsoft Entra ID -> App registrations -> New registration.
- Name: e.g. "Varman control plane".
- Supported account types:
  - **Single workspace** (one tenant, the common local model): "Accounts in this
    organizational directory only".
  - **Each customer org has its own Entra tenant** (true multi-tenant SaaS):
    "Accounts in any organizational directory (multitenant)".
- Redirect URI: platform **Web**, value `https://<your-host>/auth/callback`
  (local: `http://127.0.0.1:8080/auth/callback`). You can add several (one per
  host). This must match `ENTRA_REDIRECT_URI` exactly.
- Register. Copy the **Application (client) ID** and **Directory (tenant) ID**
  from the Overview page.

### 2. Client secret
Certificates & secrets -> Client secrets -> New client secret. Copy the secret
**Value** immediately (shown once). This is a confidential web app; the secret
lives only on the server.

### 3. API permissions
APIs my organization uses / Microsoft Graph:
- **For login (delegated):** `openid`, `profile`, `email`, `User.Read`.
- **For group-based role mapping (application / app-only):** `GroupMember.Read.All`
  and `User.Read.All` (Application permissions, not delegated).
Then click **Grant admin consent** for the tenant. The application permissions do
nothing until an admin consents.

### 4. Make the email claim reliable (recommended)
Token configuration -> Add optional claim -> ID -> `email` (and `upn` if you
like). Guest/members without a set `mail` otherwise land in `preferred_username`,
which varman also reads, but adding the `email` optional claim is cleaner.

### 5. (Optional) App roles / group claims
If you later use the org group mapping, either emit **group** claims
(Token configuration -> Add groups claim) or define **App roles**
(App roles -> Create) and assign users/groups under Enterprise applications ->
your app -> Users and roles.

### 6. Map the values to varman environment variables
Set these before starting `varman-server`:
- `ENTRA_TENANT_ID` = Directory (tenant) ID, or `contoso.onmicrosoft.com`. For a
  multitenant app that signs in users from any org, use `organizations` (or
  `common`) here.
- `ENTRA_CLIENT_ID` = Application (client) ID.
- `ENTRA_CLIENT_SECRET` = the secret Value from step 2.
- `ENTRA_REDIRECT_URI` = the exact redirect URI from step 1 (optional; defaults
  to `http://127.0.0.1:8080/auth/callback`).

Who may sign in is **not** configured in Azure: it is read live from the
workspace tenant's `tenant_settings` (primary-contact email column + `dpo_email`
in `profile_json`), i.e. whatever was entered on the Create-organisation /
Organisation screen. To change who can log in, change those emails in the app.

### 7. Verify
- Restart the server with the env set. `GET /auth/session` should report
  `login_available: true`; the console shows a Sign-in button.
- Click Sign in -> you are redirected to Microsoft, authenticate as the primary
  contact or DPO -> you land back on the console, signed in. Any other account is
  refused with 403.

## Org's OWN Entra tenant (per-customer, group-based roles)

Two deployment shapes:

- **Single workspace / single tenant (local default):** users all live in your
  one Entra tenant; the email gate (contact + DPO) is the whole story. Nothing
  more to do in Azure beyond the steps above. `ENTRA_TENANT_ID` = that tenant.

- **Multi-tenant SaaS (each customer org brings its own Entra tenant):**
  1. Register the app as **multitenant** (step 1) and set `ENTRA_TENANT_ID` to
     `organizations`.
  2. Each customer's Entra **admin** must consent to the app in their tenant.
     That is what the `/auth/entra/consent-url` + `/auth/entra/consented`
     endpoints are for: varman produces the admin-consent URL
     (`https://login.microsoftonline.com/<org-tenant>/adminconsent?client_id=...`),
     the org admin approves, and the app is then provisioned in their tenant.
  3. After consent, the org's group memberships are read app-only via
     `/auth/entra/groups` (Graph `memberOf`) and mapped to varman roles through
     the `/auth/entra/bindings` configuration. This group->role layer sits on top
     of the contact/DPO sign-in and is scaffolded but not part of the current
     slice.

## Verified vs pending

- **Verified locally:** config gating (503 when unset), the `/authorize` redirect
  construction, `login_available`, and the CSRF `state` check (403 on mismatch).
- **Needs a real Entra app (cannot be exercised locally):** the actual code
  exchange, id_token decode, and the email gate admitting the contact/DPO.

## Hardening still to do

- **Verify the id_token signature** against the tenant JWKS (RS256) and check
  `iss` / `aud` / `exp` / `nonce`. Today the claims are decoded but not
  signature-verified; the token arrives directly from Entra's token endpoint over
  TLS during the confidential-client exchange (not via the browser), so transport
  authenticates it, but JWKS verification is the correct defence in depth.
- **Opaque, revocable server-side sessions** (pending task) instead of the signed
  stateless cookie, if you need forced logout / revocation.

## The other Entra layer: per-org tenant binding

`/auth/entra/bindings`, `/auth/entra/onboard`, `/auth/entra/consent-url`,
`/auth/entra/groups` are a separate, already-scaffolded feature: an org connects
**its own** Entra tenant so roles can be mapped from Entra **group** membership
(app-only Graph reads via `entra-client`). That is the next layer on top of the
contact/DPO sign-in built here, and was deliberately left out of this slice (it
needs the org's own tenant consent and group-to-role mapping).
