# 003 — Hosted acceptance and crash-safe release state

Date: 2026-10-08. Scope: independent MESH-showcase.

The public portfolio uses GitHub-hosted verification and manually selected releases. Each acceptance job provisions a disposable Ubuntu VM. This demonstrates Ansible, deployment and Kubernetes without a persistent public self-hosted runner or a purchased server. Fork pull requests receive read-only verification; they cannot select the manual deployment path or obtain registry write permissions.

Deployment accepts a successful main release workflow, checks out its exact source commit, verifies the image signature against repository, reusable image workflow and commit, then runs immutable digests. A correct image paired with an incorrect source revision must fail. The earlier compatibility release uses the same policy. The official Caddy digest is pinned separately and is not claimed as our own signed build.

A Linux flock descriptor is inherited by the Node deploy process and Docker children. Killing the parent does not authorize a second deployment while the child still holds it. Durable journal phases and fsynced atomic state files allow the next owner to restore the last verified baseline before applying another target. Image rollback never reverses database migrations.

Alternatives considered: a persistent runner on the developer machine would share its failure domain and increase trust exposure in this public repository; a purchased VPS would add an unwanted cost and management requirement. Separate tooling checkout was rejected because the tested release must carry the deployment implementation being executed. New tooling therefore ships in a new complete release.

Costs and limits: every hosted exercise cold-starts tools and services; its VM disappears after the job. This is neither a permanently available application nor a paid production environment. Local Docker preview remains useful for the interview. Current crash probes cover rollout, verified smoke and state commit; they do not prove every kernel/power-loss/filesystem failure. Single-node K3s is a real orchestration/network-policy lab, not physical HA.

Revisit when a persistent environment, external user access, production availability target, or a stronger backup failure domain becomes an actual requirement.
