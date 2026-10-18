# Statement of Work: Varman Shadow-Mode Pilot

This is a short, signable Statement of Work for a shadow-mode pilot of Varman, the on-prem Agent Control Plane. It is written so that a customer security team can read it in full and agree to it without further clarification.

## 1. Purpose

Run Varman in shadow mode alongside one or two of the customer's AI endpoints, inside the customer environment, to demonstrate tamper-evident, independently verifiable governance of agent traffic. No live traffic is blocked during this pilot.

## 2. Scope

- 1 to 2 governed endpoints, named in an appendix agreed by both parties.
- One owning team.
- One target compliance framework (for example EU AI Act or NIST AI RMF), drawn from Varman's catalogue of 265 controls across 12 frameworks.
- A pilot window of 4 to 8 weeks.

## 3. What is deployed

Entirely within the customer VPC / on-prem environment:

- The **control plane** (`server/`): Kyte web server with the Datastar console, backed by a Postgres instance the customer hosts.
- The **data plane** (`sidecar/`): an Envoy `ext_authz` handler plus content firewall, deployed next to the governed endpoint.

No vendor-hosted component sits in the data path.

## 4. What it touches

- The sidecar inspects prompts and tool-calls at the governed endpoint, locally.
- The control plane stores signed, hash-chained decision and violation records in the customer-hosted Postgres.
- The console is used by the customer team for policy authoring, reviewing decisions, and generating framework reports.

## 5. What it cannot do in this pilot

- It cannot block live traffic. In shadow mode, any would-be deny or step_up is recorded and downgraded to shadow. This is tested behaviour.
- It cannot exfiltrate prompts. Content inspection is edge-local; raw prompts never leave the customer environment.
- It cannot obtain the signing key. The Ed25519 signing seed is customer-held configuration and is never transmitted to the vendor.

## 6. Data handling

- **Raw prompts / tool-calls:** inspected in memory at the edge, inside the customer environment. Not sent to the vendor.
- **Decision / violation records:** signed (Ed25519 over JCS canonical bytes), hash-chained into an RFC 6962 Merkle ledger, stored in the customer-hosted Postgres.
- **Signing keys:** generated and held by the customer.
- **Vendor access:** the vendor has no standing access to customer data or keys. Any support access is time-boxed, customer-initiated, and logged.

## 7. Success metric

Varman produces an evidence pack covering N decisions (N agreed in the appendix, suggested 500 to 5,000) that the customer's security reviewer verifies **independently**, using the public key alone, confirming Ed25519 signatures and RFC 6962 inclusion and consistency proofs, with no trust placed in the Varman store or the running process.

## 8. Responsibilities

**Vendor (Varman):**
- Support deployment of the control plane and sidecar in the customer environment.
- Help author policy for the target framework.
- Provide the evidence-pack export and a verification walkthrough.

**Customer:**
- Provide and operate the governed endpoint(s).
- Host the Postgres instance.
- Generate and hold the signing key.
- Provide a representative test corpus and a named security reviewer.
- Provide an Entra tenant for SSO (noting that JWKS signature verification is still to-do in the current build; see the security questionnaire).

## 9. Exit

At the end of the window, either party may end the pilot. On exit:

- The sidecar is removed from the endpoint; the endpoint returns to its pre-pilot state.
- The customer retains the evidence pack and the Postgres data (it is theirs and in their environment).
- No customer data or keys reside with the vendor, because none were transmitted to the vendor during the pilot.

## 10. Known limitations acknowledged by both parties

The customer acknowledges that, as of this pilot, Varman: applies schema migrations manually (auto-apply in progress), stores approvals in-memory (durability in progress), has no server-side automated test suite yet, has not completed OIDC JWKS signature verification, is single-node (no HA), and has not undergone a third-party penetration test, SOC 2, or independent cryptographic audit. The shadow-mode design is chosen specifically so that these limitations cannot affect live traffic during the pilot.

## 11. Signatures

| Party | Name | Role | Date |
|-------|------|------|------|
| Customer | | | |
| Vendor | | | |
