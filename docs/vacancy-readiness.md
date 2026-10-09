# MESH-showcase against the supplied BGaming vacancy

Assessment: 9 October 2026. Scope: the vacancy supplied by the user, not a claim of direct BGaming certification. This document separates project evidence from abilities that require the candidate's own explanation and commercial history.

The project's central demonstration is external studio package → validation → release → ambiguous failure → diagnosis → reconciliation → recovery. The marketplace UI gives that backend a visible product; infrastructure exercises support that same workflow.

| Vacancy criterion | Demonstration and evidence | Honest boundary |
| --- | --- | --- |
| Strong Ruby backend | PostgreSQL invariants, idempotency, immutable agreements/artifacts, domain lease/fencing rules, independent Application ports and full runtime regression suite | Strict Clean Architecture covers Publishing execution; the whole backend is a modular Rails monolith |
| Automation and internal tools | Ruby operator CLI, validation reports, durable dispatcher, trusted digest release pipeline, support action codes | Static package simulator, not every commercial gaming protocol |
| External studio support | English onboarding guide, stable actionable diagnostics, real peer credential rotation and unresolved lookup drill | No external studio was contacted; EN template is reviewed by the operator |
| Root cause investigation | Lost response after remote commit, credential rejection distinguished from transport failure, broken local diagnostic under missing key fixed by preserving local history | Synthetic failures; commercial incident stories must be the candidate's |
| Production deployment | Real GitHub verify/build/scan/provenance, Ubuntu deploy/smoke and rejected release recovery | Hosted ephemeral environment; no permanent production service is claimed |
| SRE and infrastructure | Mixed load with admission, eight SIGKILL boundaries, telemetry/alerts, independent VM restore and Windows key/backup custody | No provider-wide failover, physical HA or measured 30-day production SLO |
| DevOps / Kubernetes | Ansible second apply changed=0, Terraform drift repair, actual CNI deny controls and Helm rollout/rollback | Single-node cluster; Kubernetes is not proof of physical redundancy |
| Release validation / security | ZIP digest/inventory/budgets, real scanner, TLS verification, owner scope, HMAC replay, exact-image HIGH/CRITICAL gates | Not independent penetration testing or regulatory game certification |
| CS and engineering tradeoffs | Query plans/index cost at 50k history, bounded pages, lock/lease/fencing protocols, formal safety model | Explain assumptions and adversarial cases instead of only quoting passing counts |
| Frontend and other languages | Next.js/TypeScript UI, Node/SQLite peer, Ruby CLI, Python recovery/IaC helpers; browser/a11y suite | A second language has a concrete integration role, not a technology inventory |
| Effective AI development tools | Hypotheses and code proposed with AI assistance are checked through independent runtime assertions and CI; failed probes are investigated | The candidate must explain and take responsibility for the code; AI-generated EN text does not prove spoken English |
| Communication and ownership | [Partner guide](partner-support.md), factual EN support update, RU postmortem and exact proof/limits | Five years of commercial experience, teamwork and interviews cannot be manufactured by repository content |

## Latest support changes

The audit found two application-level support gaps: missing local credentials made the diagnostic itself fail; partner 401/403 was reduced to a generic HTTP status failure. DeploymentDiagnostic now preserves local history and reports configuration availability separately. The HTTP adapter translates authentication rejection into a domain integration code while retaining unknown.

The read model and OpenAPI distinguish unavailable fingerprint (null) from a changed fingerprint (false). The UI offers a factual English partner update and explicitly says that this diagnostic did not query the partner. Closed failures do not receive a resume instruction. Inputs with empty, oversized or header-breaking credentials fail before network I/O.

The live disposable-peer drill has passed locally: one remote POST, one remote result through timeout, key rotation, process replacement, auth rejection, stale worker completion, unavailable peer and 404. GitHub acceptance and its archived exact source/report hashes are recorded after the current checks complete. Existing infrastructure evidence stays bound to its original release f15af36; it is not silently attributed to these new source changes.

## What counts as ready to show

Use [the 15-minute walkthrough](interview-demo.md), [Clean Architecture map](clean-architecture.md), [quality criteria](quality-bar.md) and [execution status](execution-status.md). Every major claim has a concrete code path, a failure exercise, its measurement and its limit. Another engineer can run the checked commands without the owner's private infrastructure setup.

A successful showcase is finite: the existing system's stated guarantees hold under its tested failure model. “10/10 under every imaginable criterion” is not an engineering acceptance criterion. It would include mutually incompatible goals and unbounded production conditions. Neither adding unrelated technologies nor presenting a synthetic exercise as commercial work strengthens this application.

Before interviewing, the candidate still needs to rehearse independently: explain the invariant in Ruby/SQL, show the failure, read the report, and state why the recovery is safe. Prepare two real commercial stories with personal responsibility and measured outcomes, and practise an English partner conversation. Those are candidate preparation tasks, not features an agent can implement.

The owned candidate/release catalog remains readable during credential or trust unavailability. Validation exposes null input compatibility and a stable configuration error; new validation/publication commands remain blocked. The UI distinguishes unavailable configuration from changed inputs.
