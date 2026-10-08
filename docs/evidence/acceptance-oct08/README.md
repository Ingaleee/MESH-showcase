# Accepted hosted evidence

Accepted application/release source: `7f7a0e364983699cf95e83b04414fe3ef11c5f04`.
Later documentation/evidence commits are not claimed as a newly executed registry release.

| Workflow | Actual result | Reports |
| --- | --- | --- |
| [CI 37834689919](https://github.com/Ingaleee/MESH-showcase/actions/runs/37834689919) | 131 Ruby and native examples, 13 browser passes, zero skips/flaky, live incident and restore | [Manifest](hosted/ci/manifest.json) |
| [Release 37834690626](https://github.com/Ingaleee/MESH-showcase/actions/runs/37834690626) | Signed GHCR images; zero HIGH/CRITICAL in five exact digests including unfixed | [Release](hosted/release/release.json), [scan](hosted/release/image-security.json) |
| [Ubuntu 37837289487](https://github.com/Ingaleee/MESH-showcase/actions/runs/37837289487) | changed=0, verified provenance, previous runtime/new schema, business/files/SQL guards, bad image rollback, three SIGKILL recoveries | [Manifest](hosted/ubuntu/manifest.json), [runtime](hosted/ubuntu/runtime-and-rollback.json), [crash](hosted/ubuntu/crash-recovery.json) |
| [Kubernetes 37837294244](https://github.com/Ingaleee/MESH-showcase/actions/runs/37837294244) | Terraform drift/repair, migrations, CNI controls, queue/DB recovery, rollout and Helm rollback | [Summary](hosted/kubernetes/summary.json), [history](hosted/kubernetes/helm-history.json) |

```powershell
node scripts/check-hosted-acceptance.mjs
```

The checker derives test counts from downloaded reports and requires no skips/failures/flaky scenarios. It checks source/run correspondence, recorded hashes, security inventory, verified provenance identities, runtime digests, preserved data, crash outcomes and failed/deployed Helm history. Altering a report breaks its checksum. This validates this acceptance archive, not the current checkout's behavior after arbitrary future edits.

Original workflow artifacts have 30-day retention. Selected sanitized reports are preserved in Git. Publishing recovery paths are removed; their original and published report hashes are distinct in the manifest. Execution context comes from the actual workflow run. A legacy report field saying Docker Desktop is not interpreted as authoritative host evidence for the hosted run.

The five local reports beside this file retain their original timestamps and scopes. Their manifest identifies when they were recorded; that SHA is not presented as an exact execution revision for every local report. [Failed attempts](failed-attempts.json) remain failures.

These runs prove a bounded synthetic lab: ephemeral hosted Ubuntu, one-node K3s, same-host quiescent DB/files restore and a live independent partner process. They do not prove physical HA, lost-VM/offsite/PITR recovery, sustained production SLO, mixed-load capacity, the entire crash matrix or personal commercial experience. See [the full quality criteria](../../quality-bar.md).
