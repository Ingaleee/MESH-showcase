import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(process.argv[2] ?? "docs/evidence/reliability-oct09");
const kinds = ["ci", "release", "ubuntu", "recovery", "kubernetes"];
const accepted = {};
for (const kind of kinds) {
  const manifest = JSON.parse(await readFile(path.join(root, kind, "manifest.json"), "utf8"));
  assert.equal(manifest.workflow_run.status, "completed");
  assert.equal(manifest.workflow_run.conclusion, "success");
  assert.equal(
    manifest.workflow_run.html_url,
    "https://github.com/Ingaleee/MESH-showcase/actions/runs/" + manifest.workflow_run.id,
  );
  const files = {};
  for (const entry of manifest.reports) {
    assert.equal(path.basename(entry.file), entry.file);
    const raw = await readFile(path.join(root, kind, entry.file));
    assert.equal(
      createHash("sha256").update(raw).digest("hex"),
      entry.sha256,
      kind + "/" + entry.file,
    );
    files[entry.file] = entry.file.endsWith(".json") ? JSON.parse(raw) : raw.toString();
  }
  accepted[kind] = { manifest, files };
}
const release = accepted.release.files["release.json"];
for (const kind of ["ci", "release"])
  assert.equal(accepted[kind].manifest.workflow_run.head_sha, release.revision);
for (const file of ["rspec.json", "rspec-native.json"]) {
  const s = accepted.ci.files[file].summary;
  assert.ok(s.example_count > 0);
  assert.equal(s.failure_count + s.pending_count + s.errors_outside_of_examples_count, 0);
}
const browser = accepted.ci.files["playwright.json"].stats;
assert.ok(browser.expected > 0);
assert.equal(browser.unexpected + browser.flaky + browser.skipped, 0);
assert.equal(accepted.ci.files["worker-incident-summary.json"].success, true);
for (const name of ["user_outcome_firing", "user_outcome_resolved"])
  assert.ok(accepted.ci.files["worker-incident-summary.json"][name]);
for (const [name, image] of Object.entries(release.images)) {
  const scan = accepted.release.files["image-security.json"].images[name];
  assert.equal(scan.image, image);
  assert.equal(scan.findings, 0);
  assert.equal(scan.scan_exit_code, 0);
}
const workload = accepted.ubuntu.files["mixed-load.json"];
assert.equal(workload.phases.length, 5);
assert.equal(workload.phases[0].dropped_arrivals, 0);
assert.ok(workload.phases[0].p95_ms < workload.config.baseline_max_p95_ms);
assert.ok(workload.samples.some((sample) => sample.status === 429));
assert.ok(
  workload.telemetry.some((sample) => sample.pg?.lock_waiters > 0 && sample.containers?.length > 0),
);
assert.ok(
  Object.keys(workload.phases[0].statuses).every((status) => ["200", "201"].includes(status)),
);
for (const key of ["projects", "events", "processed", "notifications"])
  assert.equal(workload.verified[key], workload.commands);
assert.equal(workload.verified.duplicate_events + workload.verified.duplicate_effects, 0);
assert.equal(workload.verified.pending, 0);
const crash = accepted.ubuntu.files["crash-recovery.json"];
assert.equal(crash.phases.length, 8);
for (const row of crash.phases) {
  assert.equal(row.killed_signal, "SIGKILL");
  assert.equal(row.recovered, true);
  assert.equal(row.recovered_baseline_revision, release.revision);
  assert.notEqual(row.interrupted_target_revision, release.revision);
}
for (const flag of [
  "recovery_sigkill",
  "unavailable_engine_preserved_state",
  "subsequent_recovery",
  "corrupt_journal_denied",
])
  assert.equal(crash[flag], true);
const restored = accepted.recovery.files["restored.json"];
assert.equal(restored.source_revision, release.revision);
assert.ok(restored.rto_ms <= restored.rto_target_ms);
assert.equal(restored.external_post_count_before, restored.external_post_count_after);
for (const flag of [
  "restored_pending_reconciled",
  "private_http_artifact_verified",
  "callback_replay_deduplicated",
  "post_snapshot_local_marker_lost_as_declared",
  "source_job_finished_before_target_started",
])
  assert.equal(restored[flag], true);
assert.ok(restored.private_objects_verified > 0);
assert.equal(restored.runtime_database_role, "mesh_runtime");
assert.equal(restored.post_restore_notification_effects, 1);
assert.equal(restored.external_post_count_after_workers, restored.external_post_count_before);
for (const flag of [
  "runtime_private_http_artifact_verified",
  "anonymous_private_download_denied",
  "background_processing_resumed",
  "post_restore_command_replayed_once",
])
  assert.equal(restored[flag], true);
for (const flag of ["wrong_key", "truncated", "tampered", "missing_object"])
  assert.equal(restored.negative_controls[flag], true);
const isolation = accepted.recovery.files["vm-isolation.json"];
assert.notEqual(isolation.source.vm_uuid, isolation.target.vm_uuid);
const custody = accepted.recovery.files["independent-custody-proof.json"];
assert.equal(custody.github_api_used_for_verification, false);
assert.equal(custody.key_read_from_windows_credential_manager, true);
assert.equal(custody.only_encrypted_backup_persisted, true);
assert.equal(custody.inventories_verified.length, 2);
for (const row of custody.inventories_verified) assert.equal(row.source_revision, release.revision);
const kube = accepted.kubernetes.files["summary.json"];
assert.equal(kube.release_revision, release.revision);
for (const flag of [
  "terraform_drift_detected_and_repaired",
  "migration_completed_before_application",
  "positive_api_and_db",
  "untrusted_ingress_denied",
  "unapproved_egress_denied_with_positive_control",
  "worker_50_once_only_effects",
  "database_outage_ready_503_live_200",
  "outage_preserved_api_uids_and_restarts",
  "alpine_rollout",
  "broken_upgrade_rejected",
  "registry_digest_restored",
])
  assert.equal(kube[flag], true, flag);
assert.deepEqual(kube.images, release.images);
assert.match(accepted.ubuntu.files["ansible-second.log"], /changed=0 .*unreachable=0 .*failed=0/);
assert.deepEqual(accepted.ubuntu.files["runtime-and-rollback.json"].release, release.images);
for (const kind of ["ubuntu", "recovery"]) {
  const rows = accepted[kind].files["attestation-api.json"];
  const expected = release.images.api.split("@sha256:")[1];
  assert.ok(
    rows.some((row) => {
      const result = row.verificationResult;
      return (
        result.statement.subject.some((subject) => subject.digest.sha256 === expected) &&
        JSON.stringify(result).includes(release.revision)
      );
    }),
    "Attestation must bind this release digest and source revision",
  );
}

console.log(
  "Reliability archive verified: exact release, mixed load, crash transitions, fresh VM/key custody and user outcome alerts.",
);
