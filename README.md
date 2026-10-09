# MESH · Integration & Release Lab

[![Verification](https://github.com/Ingaleee/MESH-showcase/actions/workflows/verify.yml/badge.svg)](https://github.com/Ingaleee/MESH-showcase/actions/workflows/verify.yml)

**A Ruby/Rails engineering showcase for external integrations, release automation and recovery.**

MESH starts as a creator marketplace: brief → proposal → agreement → versioned delivery → acceptance. Its Publishing lab demonstrates what happens when a partner accepts a release but the response is lost: retain the operation, diagnose uncertainty and reconcile without publishing twice.

[**Watch the short demo**](https://ingaleee.github.io/MESH-showcase/) · [Screenshot walkthrough](docs/visual-walkthrough.md) · [Verified results](docs/partner-support-acceptance-oct09.md)

[![Real Publishing workflow: package validation, uncertain release and safe recovery](docs/presentation/assets/publishing.jpg)](https://ingaleee.github.io/MESH-showcase/)

_Actual application recording with English captions. The application UI is in Russian. The public presentation is static; it does not expose the backend or real partner credentials._

## What the project demonstrates

| Engineering problem             | Implementation                                                                                                    |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Repeated or concurrent commands | Idempotency keys, PostgreSQL constraints, row locks and immutable agreements                                      |
| Uncertain external effects      | Durable operation identity, lookup-only reconciliation, lease fencing and signed callback deduplication           |
| Unsafe or stale release inputs  | Private digest-bound ZIP artifacts, bounded validation, real ClamAV, policy/configuration fingerprint             |
| Reliable delivery               | Outbox, Solid Queue, durable dispatcher and metrics that include unfinished work                                  |
| Trusted release and recovery    | Signed image provenance, deployment by digest, migration/runtime DB roles, rollback journal and encrypted restore |

**Architecture:** eight-domain modular Rails monolith. Publishing execution has framework-independent Domain/Application layers with explicit ports and PostgreSQL/HTTP/storage adapters. [Code map and tradeoffs](docs/clean-architecture.md).

**Stack:** Ruby / Rails · PostgreSQL · Solid Queue · Next.js / TypeScript · Node.js partner simulator · Docker · GitHub Actions · Ansible · Terraform · Helm / Kubernetes · Prometheus / Grafana / Alertmanager.

## Executed evidence

The accepted application release is `3d849af`. Later documentation commits retain that release identity.

| Verification           | Result                                                                                                                             | Evidence                                                                               |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Ruby and browser       | 153 Ruby examples in each of development and native Alpine; 13 browser scenarios; no failures, pending, skipped or flaky scenarios | [CI](https://github.com/Ingaleee/MESH-showcase/actions/runs/37909615272)               |
| Exact-image security   | Five runtime digests scanned; zero HIGH/CRITICAL findings, including unfixed; four signed build outputs                            | [Release](https://github.com/Ingaleee/MESH-showcase/actions/runs/37892419510)          |
| Ubuntu deployment      | Ansible second apply changed=0, mixed load, rejected release rollback and eight SIGKILL recovery points                            | [Deployment](https://github.com/Ingaleee/MESH-showcase/actions/runs/37898543604)       |
| Kubernetes             | Terraform drift repair, real NetworkPolicy controls, readiness/liveness and rollout/rollback                                       | [Cluster exercise](https://github.com/Ingaleee/MESH-showcase/actions/runs/37898550160) |
| Clean demo preparation | Fresh Ubuntu checkout; actual npm run demo; all 17 stages and 4 browser checks passed                                              | [Cold preparation](https://github.com/Ingaleee/MESH-showcase/actions/runs/37909616516) |
| Separate-VM recovery   | Primary/queue/private artifacts restored; API/workers resumed; no repeated external publication                                    | [Recovery](https://github.com/Ingaleee/MESH-showcase/actions/runs/37898547328)         |

The [clean-run preparation and gallery](docs/visual-walkthrough.md) distinguish fresh checkout verification from an existing local preview. Reports retain source revisions, workload/fault scope, original artifact digests and per-file hashes. Verify the saved catalogue with `npm run test:partner-support:evidence`. A passing scan is a dated observation, not a permanent security guarantee.

## Run locally

Requirements: Node.js 22/npm, Docker with Linux containers, registry access, Microsoft Edge on Windows (or the matching Playwright Chromium runtime on Linux) and enough memory for the application plus ClamAV. Prepare before the interview; the command includes builds and can take several minutes.

```sh
npm run demo
```

Open [Publishing](http://localhost:3200/publishing), [marketplace](http://localhost:3200/) and [Grafana](http://localhost:32092/d/mesh-reliability). Synthetic operator: `ops@mesh.local` / `MeshDemo2026!` — lab credentials only.

```sh
npm run demo:publishing       # real partner, lost response, reconciliation and rollback
npm run demo:partner-support # disposable peer: credential rotation, fencing and uncertainty
npm run demo:incident        # worker outage, delivered alert and once-only recovery
```

[Setup and environment guide](SHOWCASE.md) · [15-minute technical walkthrough](docs/interview-demo.md) · [Detailed marketplace guide (RU)](docs/marketplace-guide.ru.md)

## Scope and limits

This is a reproducible engineering lab, not a claim of operating a commercial gaming platform. Uploaded code is never executed; payments and partners are simulators. Hosted environments are ephemeral, Kubernetes is single-node, and restore uses a quiescent snapshot with a small fixture. Multi-node HA, online WAL/PITR, large-restore throughput, permanent backup retention and a long production SLO window are **not demonstrated**.

## Read deeper

- [Visual walkthrough: screens, failure sequence and transcript](docs/visual-walkthrough.md)
- [Publishing guarantees and Ruby CLI](docs/publishing-lab.md)
- [English partner onboarding/support guide](docs/partner-support.md)
- [Threat model](docs/threat-model.md) and [current acceptance](docs/partner-support-acceptance-oct09.md)
- [Fit against the supplied engineering vacancy](docs/vacancy-readiness.md)
