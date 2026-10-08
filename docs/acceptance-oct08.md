# Acceptance work on 8 October 2026

This log separates executed checks from queued release/deployment work. The earlier evidence remains historical.

| Guarantee                               | Implementation                                                                                                      | Executed evidence                                                                                              |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Confirmation is complete                | NULL-safe check, active partner/sequence binding, confirmed rollback basis                                          | Direct SQL regression cases; runtime-role probe is also in the release exercise                                |
| History remains accessible              | Signed owner/kind cursor; total timestamp/UUID order; separate active read; order indexes                           | Tied timestamps, insert between pages, cursor substitution, 50k SQL/Ruby samples                               |
| An upload is replayable                 | Durable intent and blob metadata committed before storage I/O; bounded upload; fenced lease                         | Bytes written before local completion, same-key retry, fingerprint conflict, no open transaction during upload |
| Cleanup preserves references            | Minimum two-day grace, dry-run default, tombstone before deletion, direct reference checks and SQL reference guards | Referenced candidate/attachments survive; reclaimed objects reject new references                              |
| Deployment is recoverable               | Linux flock inherited by children, fsynced atomic JSON and journal, baseline recovery                               | State tests passed; Linux SIGKILL/child-lock tests execute in hosted jobs                                      |
| Backup authenticates before extraction  | Streamed AES-256-GCM, two DB dumps, immutable byte inventory, separate key file                                     | Wrong key and modified ciphertext rejected; clean DBs/files restored; HTTP private artifact verified           |
| External outcome survives local restore | Recovery changes unconfirmed restored intents to unknown and only looks up the original operation                   | Partner POST counter unchanged (36 before/after in the current local report)                                   |
| Telemetry survives restart              | Named volumes; Prometheus 7d/512MB; Alertmanager 120h; receipts limited to two 8MB files                            | Fixed historical sample, active silence and delivered receipts survived restart                                |

Cleanup intentionally skips uploading leases and finalized intents. A stale uploading intent is retried by its original key; this command does not purge arbitrary historical blobs or files without metadata. Grace must be at least the supported backup recovery window. The two-day default is a lab policy, not an assertion of offsite recovery retention.

The restored partner process and PostgreSQL run on the same physical host. The exercise proves reconciliation against independently advanced external state and clean local restore. It does not prove whole-host disaster recovery or production HA. Secrets and encrypted snapshots are ignored local state; only sanitized reports are published.

## Release trust

Public portfolio jobs run on GitHub-hosted Ubuntu. Persistent self-hosted runner configuration is retained only for an explicitly trusted private repository. Deployment validates a successful main release workflow, checks out its exact commit, verifies signed image provenance against repo/workflow/source revision, rejects a false revision and uses immutable digests. The earlier release, when provided for compatibility, passes the same signature policy.

Ansible's first actual deployment attempt failed because the package index cache predated a newly changed Docker apt source. The role now explicitly refreshes indexes after that change. Both apply runs fail immediately on errors; the second must report changed=0 and failed=0. A Docker restart is part of provisioning before the stand starts.

## Commands

Run from the independent MESH-showcase checkout:

```powershell
npm run contract:check
docker compose exec -T -e RAILS_ENV=test api bundle exec rspec
docker compose exec -T api bin/rails publishing:uploads:reclaim
node scripts/check-telemetry-retention.mjs
node scripts/check-publishing-continuity.mjs
npm run demo:incident
```

Cleanup deletion requires APPLY=1; the default only inventories eligible intents. Publishing continuity stops this project's API/worker/dispatcher and restores them in finally. It adds synthetic records and never resets the main product.

For hosted release/deployment/Kubernetes, use the repository's manual workflows. release_run_id must refer to a successful image release; no VM purchase, SSH setup or persistent public runner is needed. A hosted VM exists only for its job. Current job outcomes are recorded in execution-status.md after completion.
