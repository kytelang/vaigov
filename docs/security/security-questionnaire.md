# Varman Vendor Security Questionnaire

SIG-lite / CAIQ-style responses. Grouped by domain. Where the honest answer is "not yet", it says so and names the roadmap item. A reviewer should be able to trust the "yes" answers precisely because the "no" answers are not hidden.

## Data handling and encryption

**Q: What customer data does the product process?**
A: At the edge, the sidecar inspects prompts and tool-calls locally. The control plane stores signed decision and violation records. Raw prompts are not stored as traffic dumps; decision/violation records are the signed outputs.

**Q: Does any customer data leave the customer environment?**
A: No. Varman is deployed on-prem / in-VPC. Raw prompts are inspected edge-local and never leave. Decision records live in the customer-hosted Postgres. There is no vendor-hosted component in the data path.

**Q: Is data encrypted in transit?**
A: Yes, TLS 1.3.

**Q: Is data encrypted at rest?**
A: At-rest encryption is provided by the customer-hosted Postgres and the customer's storage layer; Varman relies on the customer's database and disk encryption rather than implementing its own at-rest layer. Records are additionally signed and hash-chained, which provides integrity (not confidentiality) independent of storage.

**Q: Does the vendor have access to customer data?**
A: No standing access. Any support access is customer-initiated, time-boxed, and logged.

## Identity and access

**Q: How do users authenticate?**
A: Entra / OIDC (SSO).

**Q: Are OIDC tokens cryptographically verified?**
A: Not yet in the current Kyte port. JWKS signature verification is **to-do**. Tokens are parsed but signatures are not yet verified. Roadmap item: implement JWKS verification before any enforcement use. This is disclosed as an open gap.

**Q: How is multi-tenancy isolated?**
A: Tenant is derived from the authenticated session, not from a client-supplied header, which prevents cross-tenant header spoofing.

**Q: Is there role-based access control for policy authoring and approvals?**
A: Policy authoring and approvals run through the control plane console. Note that the approvals store is currently in-memory (durability in progress), so approval state is not yet persistent across restarts.

## Application security

**Q: Describe the SDLC and testing posture.**
A: The trust core library (Ed25519, SHA-256, RFC 6962 Merkle ledger, JCS canonicalisation) has 70/70 unit tests passing. Server-side automated tests are **not yet** in place (roadmap item, in progress), and the single end-to-end script is currently being repaired. This is the weakest area today and is disclosed as such.

**Q: Memory safety.**
A: Varman is implemented in Kyte, whose compiler toolchain is developed with an AddressSanitizer (ASAN) gate as part of its correctness process. This reduces the class of memory-safety defects relative to an unchecked C/C++ build, but it is not a substitute for a security audit of Varman itself.

**Q: Dependency and supply-chain scanning.**
A: SBOM generation and deploy packaging are a **roadmap item** (TODO) targeted before pilot deployment, so the customer receives an inventoried artefact. Automated dependency scanning is not yet wired in; this is disclosed.

**Q: Secure HTTP headers.**
A: The console sets a Content-Security-Policy and secure response headers.

## Cryptography and key management

**Q: What primitives are used?**
A: Ed25519 for signing, SHA-256 for hashing, JCS for canonical bytes, and an RFC 6962 Merkle ledger with inclusion and consistency proofs.

**Q: Who holds the signing key?**
A: The customer. The Ed25519 signing seed is customer-held configuration and never leaves the customer environment. The vendor never receives it.

**Q: Can audit evidence be verified without trusting the vendor?**
A: Yes. Evidence packs verify independently using the public key alone, with no need to trust the Varman store or a running Varman process.

**Q: Has the cryptographic implementation been independently audited?**
A: Not yet. There is no independent cryptographic audit (roadmap item). The 70/70 library unit tests are self-testing, not an external audit.

## Logging and monitoring

**Q: What is logged?**
A: Decisions and violations are recorded as signed, hash-chained records. Operational logging exists but structured logs and health/metrics endpoints are only partially in place; fuller observability is a **roadmap item** (TODO) for pilot operability.

**Q: Is the audit log tamper-evident?**
A: Yes. The ledger is append-only with RFC 6962 inclusion and consistency proofs, and records are signed. Tampering is cryptographically detectable (see the threat model).

## Availability and BCDR

**Q: Is the service highly available?**
A: No. Single-node only; no HA yet (roadmap item). Loss of the single control-plane node is an availability event.

**Q: What happens if the control plane is unreachable?**
A: The data plane fails closed to the last-good configuration rather than dropping governance. In shadow mode, that last-good policy still does not block traffic.

**Q: Backup and restore.**
A: A documented backup/restore procedure for the Postgres store and ledger is a **roadmap item** (TODO) before pilot.

**Q: Do schema migrations apply cleanly on deploy/upgrade?**
A: Auto-apply from the binary is **in progress**. Today, migrations may require a manual step; the customer is informed during deployment.

## Compliance and certifications

**Q: Do you hold SOC 2, ISO 27001, or similar?**
A: No, none yet. These are roadmap items, not current certifications. This is stated plainly.

**Q: What compliance tooling does the product provide?**
A: A catalogue of 265 controls across 12 frameworks (including EU AI Act, NIST AI RMF, ISO 42001, ISO 27001, GDPR, SOC 2, and Colorado / NYC / Canada AI laws), with real article citations and cross-framework crosswalks. Framework reports derive from a GRC checklist combined with runtime decision and evidence coverage. This is a reporting and mapping capability for the customer's own governance; it is not a vendor certification.

**Q: Has the product had a third-party penetration test?**
A: No, not yet (roadmap item). Disclosed.

**Q: Are there production references?**
A: None yet. Varman is at the design-partner pilot stage.

## Deployment and isolation

**Q: Where does the product run?**
A: Entirely in the customer VPC / on-prem. Control plane plus sidecar. The customer hosts Postgres and holds the keys.

**Q: Is there a tenant boundary between the vendor and the customer?**
A: There is no shared vendor tenancy; each customer runs their own isolated deployment in their own environment. The vendor does not operate a multi-tenant hosted service for this product.

**Q: Can the product be removed cleanly?**
A: Yes. Removing the sidecar returns the endpoint to its pre-pilot state; the Postgres data and evidence packs remain with the customer.
