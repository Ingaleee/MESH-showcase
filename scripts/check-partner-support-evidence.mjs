import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(process.argv[2] ?? "docs/evidence/partner-support-oct09");
// Reuse the established infrastructure proof gate on this new archive.
// Historical reliability evidence remains bound to its own source revision.
execFileSync(process.execPath, ["scripts/check-reliability-evidence.mjs", root], {
  stdio: "inherit",
  windowsHide: true,
});
const accepted = {};
for (const kind of ["ci", "release", "ubuntu"]) {
  const manifest = JSON.parse(await readFile(path.join(root, kind, "manifest.json"), "utf8"));
  assert.equal(manifest.kind, kind);
  assert.equal(manifest.workflow_run.status, "completed");
  assert.equal(manifest.workflow_run.conclusion, "success");
  assert.match(manifest.workflow_run.head_sha, /^[a-f0-9]{40}$/);
  assert.equal(
    manifest.workflow_run.html_url,
    "https://github.com/Ingaleee/MESH-showcase/actions/runs/" + manifest.workflow_run.id,
  );
  for (const artifact of [manifest.artifact, ...(manifest.related_artifacts ?? [])]) {
    assert.match(artifact.downloaded_archive_sha256, /^[a-f0-9]{64}$/);
    assert.equal("sha256:" + artifact.downloaded_archive_sha256, artifact.digest);
  }
  const files = {};
  for (const entry of manifest.reports) {
    assert.equal(path.basename(entry.file), entry.file);
    assert.ok(!Object.hasOwn(files, entry.file), "Duplicate report path.");
    const raw = await readFile(path.join(root, kind, entry.file));
    assert.equal(createHash("sha256").update(raw).digest("hex"), entry.sha256, entry.file);
    files[entry.file] = entry.file.endsWith(".json") ? JSON.parse(raw) : raw.toString();
  }
  accepted[kind] = { manifest, files };
}
const ci = accepted.ci.files;
const revision = accepted.ci.manifest.workflow_run.head_sha;
assert.equal(ci["context.json"].revision, revision);
assert.equal(String(ci["context.json"].run_id), String(accepted.ci.manifest.workflow_run.id));
for (const name of ["rspec.json", "rspec-native.json"]) {
  const summary = ci[name].summary;
  assert.equal(summary.example_count, 153);
  assert.equal(
    summary.failure_count + summary.pending_count + summary.errors_outside_of_examples_count,
    0,
  );
}
assert.equal(ci["playwright.json"].stats.expected, 13);
assert.equal(
  ci["playwright.json"].stats.unexpected +
    ci["playwright.json"].stats.skipped +
    ci["playwright.json"].stats.flaky,
  0,
);
const layouts = ci["browser-layouts.json"];
assert.deepEqual(
  layouts.map((row) => row.viewport),
  [1440, 1024, 390],
);
for (const row of layouts) {
  assert.ok(row.scroll_width <= row.viewport + 1);
  assert.equal(row.fonts, "loaded");
  assert.deepEqual(row.overflowing_elements, []);
}
const drill = ci["partner-support.json"];
assert.equal(drill.success, true);
assert.equal(drill.disposable_resources_removed, true);
assert.equal(drill.dirty_source, false);
assert.equal(drill.revision, revision);
assert.deepEqual(Object.keys(drill.phases), ["prepare", "rotated", "unavailable", "absent"]);
const expectedChecks = {
  prepare: ["real_scanner_passed", "remote_accepted_once_before_timeout", "local_outcome_unknown"],
  rotated: [
    "auth_rejection_kept_unknown",
    "old_http_credential_denied",
    "new_http_credential_accepted",
    "stale_validation_blocked",
    "old_worker_result_fenced",
    "old_failure_fenced",
    "expired_lease_looked_up",
    "old_callback_denied",
    "rotated_callback_replay_once",
    "secret_outage_preserved_local_report",
  ],
  unavailable: ["unavailable_peer_kept_unknown", "original_operation_preserved"],
  absent: ["absent_lookup_kept_unknown", "no_republication", "read_only_diagnostic"],
};
for (const [phase, checks] of Object.entries(expectedChecks)) {
  assert.equal(drill.phases[phase].success, true);
  for (const check of checks)
    assert.equal(drill.phases[phase].checks[check], true, phase + "/" + check);
}
assert.equal(drill.phases.prepare.operation_id, drill.phases.rotated.operation_id);
assert.equal(drill.phases.rotated.checks.remote_posts, 1);
assert.equal(drill.phases.absent.remote_posts, 1);
assert.equal(drill.phases.absent.remote_effects, 1);
assert.equal(
  drill.phases.absent.diagnostic.operation_id,
  drill.phases.rotated.uncertain_operation_id,
);
assert.equal(
  drill.phases.rotated.rejected_credential_diagnostic.action_code,
  "restore_configuration",
);
assert.equal(
  drill.phases.rotated.rejected_credential_diagnostic.last_error,
  "PARTNER_AUTH_REJECTED",
);
assert.equal(drill.phases.rotated.diagnostic.configuration_error, "PARTNER_CREDENTIAL_UNAVAILABLE");
assert.equal(drill.phases.rotated.diagnostic.current_inputs_match, null);
assert.equal(drill.phases.rotated.diagnostic.state, "confirmed");
for (const phase of ["unavailable", "absent"]) {
  const diagnostic = drill.phases[phase].diagnostic;
  assert.equal(diagnostic.state, "unknown");
  assert.equal(diagnostic.action_code, "lookup_only");
  assert.equal(diagnostic.remote_state_queried, false);
  assert.ok(diagnostic.support_update_en.includes(diagnostic.operation_id));
}
assert.equal(drill.phases.absent.diagnostic.last_error, "PARTNER_OUTCOME_UNKNOWN");
const expectedSources = [
  "apps/api/script/partner_support_drill.rb",
  "apps/api/packs/publishing/app/services/publishing/deployment_diagnostic.rb",
  "apps/partner/src/server.ts",
  "apps/api/packs/publishing/app/services/publishing/settings.rb",
  "apps/api/packs/publishing/app/domain/publishing/domain/deployment_rules.rb",
  "apps/api/packs/publishing/app/services/publishing/apply_observation.rb",
  "apps/api/packs/publishing/app/infrastructure/publishing/infrastructure/deployment_partner.rb",
  "scripts/run-partner-support-drill.mjs",
];
assert.deepEqual(Object.keys(drill.source_hashes).sort(), expectedSources.sort());
for (const [file, digest] of Object.entries(drill.source_hashes)) {
  const source = execFileSync("git", ["show", revision + ":" + file], {
    windowsHide: true,
    maxBuffer: 2 ** 20,
  });
  assert.equal(
    createHash("sha256").update(source).digest("hex"),
    digest,
    "Exact checked source: " + file,
  );
}
const release = accepted.release.files["release.json"];
assert.equal(release.revision, revision);
assert.equal(release.working_tree_dirty, false);
assert.equal(accepted.release.manifest.workflow_run.head_sha, revision);
const security = accepted.release.files["image-security.json"];
assert.equal(security.success, true);
assert.deepEqual(Object.keys(security.images).sort(), Object.keys(release.images).sort());
for (const [name, image] of Object.entries(release.images)) {
  assert.match(image, /@sha256:[a-f0-9]{64}$/);
  assert.equal(security.images[name].image, image);
  assert.equal(security.images[name].scan_exit_code + security.images[name].findings, 0);
}
const ubuntu = accepted.ubuntu.files;
assert.equal(accepted.ubuntu.manifest.workflow_run.head_sha, revision);
const runtime = ubuntu["runtime-and-rollback.json"];
assert.equal(runtime.success, true);
assert.deepEqual(runtime.release, release.images);
assert.notEqual(runtime.rejected_exit, 0);
assert.equal(runtime.previous_images_restored, true);
assert.deepEqual(runtime.data_before, runtime.data_after);
assert.equal(runtime.migration_reverted, false);
assert.ok(/changed=0.*failed=0/.test(ubuntu["ansible-second.log"]));
assert.equal(ubuntu["business-probe.json"].accepted, true);
assert.ok(Object.values(ubuntu["business-probe.json"].denied).every((value) => value === true));
assert.equal(ubuntu["tls-read-profile.json"].errors, 0);
assert.equal(ubuntu["tls-read-profile.json"].rejected_arrivals, 0);
const crashes = ubuntu["crash-recovery.json"];
assert.equal(crashes.phases.length, 8);
assert.ok(
  crashes.phases.every(
    (row) =>
      row.recovered &&
      row.killed_signal === "SIGKILL" &&
      row.recovered_baseline_revision === revision,
  ),
);
assert.equal(crashes.unavailable_engine_preserved_state, true);
assert.equal(crashes.corrupt_journal_denied, true);
// Keep the rejected run and scoped local negative control reviewable.
const rejectedRoot = path.join(root, "failed-browser");
const rejected = JSON.parse(await readFile(path.join(rejectedRoot, "manifest.json"), "utf8"));
assert.equal(rejected.workflow_run.conclusion, "failure");
assert.notEqual(rejected.workflow_run.head_sha, revision);
assert.equal("sha256:" + rejected.downloaded_archive_sha256, rejected.artifact.digest);
const rejectedFiles = {};
for (const entry of rejected.reports) {
  assert.equal(path.basename(entry.file), entry.file);
  const raw = await readFile(path.join(rejectedRoot, entry.file));
  assert.equal(createHash("sha256").update(raw).digest("hex"), entry.sha256);
  rejectedFiles[entry.file] = JSON.parse(raw);
}
assert.ok(rejectedFiles["layouts.json"].some((row) => row.scroll_width > row.viewport + 1));
const control = rejectedFiles["css-control.json"];
assert.ok(control.scope.includes("Controlled CSS"));
assert.ok(control.before.some((row) => row.scroll_width > row.viewport + 1));
assert.ok(control.after.every((row) => row.scroll_width === row.viewport));
assert.equal(control.success, true);
const checkedCss = execFileSync(
  "git",
  ["show", revision + ":apps/web/src/app/publishing/publishing.css"],
  {
    windowsHide: true,
    maxBuffer: 2 ** 20,
  },
);
assert.equal(createHash("sha256").update(checkedCss).digest("hex"), control.css_sha256);
console.log(
  "Partner support archive verified: exact source, real rotation/outage/fencing, 153+153 Ruby, browser, signed scanned release, Ubuntu, independent VM recovery and Kubernetes.",
);
