# Varman Threat Model

Audience: a customer security reviewer assessing the risk of placing Varman in-path.

Varman is unusual in three ways that drive its threat model: it sits **in the request path**, it **holds (uses) a signing key**, and it **sees plaintext prompts** at the edge. This document uses a STRIDE-style framing, states the mitigations that are actually present in the code today, and lists honestly the threats that are **not yet mitigated**. It does not claim protections that do not exist.

## Assets

| Asset | Why it matters |
|-------|----------------|
| Signing key (Ed25519 seed) | Forging it would let an attacker mint fake "authentic" evidence. Customer-held. |
| Evidence ledger integrity | The whole value proposition is a tamper-evident record. Silent rewriting would destroy it. |
| Policy integrity | If policy can be altered or bypassed, enforcement and shadow results are meaningless. |
| Prompt confidentiality | Prompts and tool-calls are sensitive; they are inspected at the edge and must not leak. |

## STRIDE analysis

### Spoofing
- **Threat:** an attacker impersonates a user or another tenant to author policy or read decisions.
- **Mitigated today:** tenant is derived from the authenticated session, not from a client-supplied header, which closes the classic cross-tenant header-spoof. Identity is Entra / OIDC.
- **Not yet mitigated:** JWKS signature verification for the OIDC tokens is still TODO in the Kyte port. Until that lands, token signatures are parsed but not cryptographically verified, so Entra SSO must be treated as not-yet-hardened. This is a prerequisite for any enforce phase.

### Tampering
- **Threat:** someone alters decision or violation records, or rewrites history in the store.
- **Mitigated today:** every decision and violation is signed with Ed25519 over JCS canonical bytes and hash-chained. The ledger is append-only with RFC 6962 inclusion and consistency proofs. The content firewall additionally chains violations with `prevSig`. Tampering is **detectable** by independent verification (see the abuse case below).
- **Residual:** detection, not prevention, at the store layer. Prevention of silent rewrite relies on the customer (or an auditor) actually running consistency verification. We recommend periodic signed-head checkpoints retained outside the primary store.

### Repudiation
- **Threat:** a party denies that a decision was made or that a record is genuine.
- **Mitigated today:** signed records over canonical bytes plus a Merkle log provide non-repudiation that can be checked with the public key alone, independent of the vendor and independent of the running system.

### Information disclosure
- **Threat:** prompts or tool-call content leak.
- **Mitigated today:** content inspection is edge-local in the sidecar; raw prompts never leave the customer environment, and the vendor has no data path to them. Transport is TLS 1.3. The console sets a Content-Security-Policy and secure headers.
- **Not yet mitigated:** no third-party penetration test has validated the console and sidecar surfaces. Treat disclosure risk as un-attested until a pen test is done.

### Denial of service
- **Threat:** the control plane is knocked over, removing governance, or the in-path sidecar is overloaded and stalls traffic.
- **Mitigated today:** the data plane fails closed to the last-good configuration when the control plane is unreachable, so loss of the control plane does not silently remove governance. In shadow mode the last-good policy still does not block, so a control-plane outage cannot start blocking traffic.
- **Not yet mitigated:** single-node only, no HA. A failure of the single control-plane node is an availability event. Capacity and latency of the in-path sidecar under load have not been independently benchmarked for the pilot workload.

### Elevation of privilege
- **Threat:** a lower-privilege user gains policy-authoring or approval rights, or bypasses the policy engine.
- **Mitigated today:** policy evaluation has explicit precedence (deny > step_up > shadow > allow) and the in-process manifest engine fails closed to deny on error, so an evaluation error does not become an accidental allow. Tenant scoping comes from the session.
- **Not yet mitigated:** approvals are currently held in-memory (durability and therefore reliable authorisation state is in progress), and there are no server-side automated tests yet, so the authorisation surface has not been regression-locked.

## Threats explicitly NOT yet mitigated (honest list)

- No third-party penetration test.
- OIDC / Entra JWKS signature verification is TODO in the Kyte port.
- Approvals store is in-memory, not yet durable.
- No high availability; single node only.
- No SOC 2, and no independent cryptographic audit of the signing and Merkle implementation (the library has 70/70 of its own unit tests passing, but that is self-testing, not an external audit).
- No production references.

These are the reasons a pilot starts in shadow mode and these items gate the move to enforcement.

## Abuse / tamper case: operator tampers with the evidence store

Scenario: a privileged operator (or an attacker who has reached the Postgres instance) edits or deletes rows in the evidence store to hide a decision or rewrite history.

Why it fails to go undetected:

1. Each record is signed with the customer-held Ed25519 key over JCS canonical bytes. An operator who edits a record cannot re-sign it without the signing seed, which is customer-held and not present in the store. Any edit invalidates the signature.
2. The ledger is an RFC 6962 Merkle log. Deleting or reordering entries breaks **inclusion** proofs for the affected records.
3. Rewriting history (as opposed to appending) breaks the **consistency** proof between an older signed head and the current head. If the customer retains periodic signed heads, a rewrite is provable, not just suspected.
4. Verification runs with the public key alone, independently of the Varman store and of any running Varman process. The operator cannot suppress the check by tampering with the server.

Result: store-level tampering is cryptographically detectable by the customer. Varman's guarantee is detection and proof, which is the correct guarantee for an audit-evidence system where the store operator is inside the trust-reduction scope.
