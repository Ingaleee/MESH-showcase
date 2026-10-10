import { spawnSync } from "node:child_process";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import assert from "node:assert/strict";
await readFile("SHOWCASE.md");
const directory = process.env.MESH_EVIDENCE_DIR
  ? process.env.MESH_EVIDENCE_DIR + "/publishing-demo"
  : "docs/evidence/publishing-demo";
await mkdir(directory, { recursive: true });
const env = await readFile(process.env.COMPOSE_ENV_FILES ?? ".env", "utf8");
const port = /^MESH_PARTNER_PORT=(.+)$/m.exec(env)?.[1] ?? "3216";
const baseURL = process.env.MESH_BASE_URL ?? "http://localhost:3200";
const token = /^MESH_PARTNER_TOKEN_SHOWCASE=(.+)$/m.exec(env)?.[1];
if (!token) throw new Error("Prepare the isolated partner credentials first.");
async function partner(path) {
  const response = await fetch("http://127.0.0.1:" + port + path, {
    headers: { Authorization: "Bearer " + token },
    signal: AbortSignal.timeout(5_000),
    redirect: "error",
  });
  assert.equal(response.status, 200);
  return response;
}
const readinessDeadline = Date.now() + 60_000;
for (;;) {
  try {
    const response = await fetch(baseURL + "/ready", {
      signal: AbortSignal.timeout(3_000),
    });
    if (response.ok) break;
  } catch {}
  if (Date.now() > readinessDeadline) throw new Error("API readiness did not recover.");
  await new Promise((resolve) => setTimeout(resolve, 1000));
}
const before = await (await partner("/state")).json();
const run = spawnSync(
  "docker",
  [
    "compose",
    "exec",
    "-T",
    "-e",
    "MESH_DEMO_ORIGIN=http://127.0.0.1:3000",
    "-e",
    "MESH_DEMO_PASSWORD=MeshDemo2026!",
    "api",
    "bundle",
    "exec",
    "ruby",
    "script/publishing_demo.rb",
  ],
  {
    encoding: "utf8",
    timeout: 180_000,
    maxBuffer: 2 ** 22,
    windowsHide: true,
  },
);
await writeFile(directory + "/cli.log", run.stdout ?? "");
if (run.error || run.status !== 0) {
  process.stderr.write(run.stderr ?? "");
  throw run.error ?? new Error("Publishing demo failed; partial CLI output preserved.");
}
const marker = "MESH_PUBLISHING_REPORT=";
const line = run.stdout.split("\n").find((row) => row.startsWith(marker));
if (!line) throw new Error("Missing publishing demo report.");
const report = JSON.parse(line.slice(marker.length));
const operationIds = [
  report.phases.normal_release.id,
  report.phases.lost_response.recovered.id,
  report.phases.rollback.id,
];
let after;
const callbackDeadline = Date.now() + 90000;
for (;;) {
  after = await (await partner("/state")).json();
  if (
    operationIds.every((id) =>
      after.callbacks.some(
        (row) => row.operation_id === id && row.last_status === 200 && row.delivered_at,
      ),
    )
  )
    break;
  if (Date.now() >= callbackDeadline)
    throw new Error(
      "Authenticated machine callbacks did not settle; inspect the partner receipt statuses.",
    );
  await new Promise((resolve) => setTimeout(resolve, 1000));
}
report.signed_callbacks_delivered = after.callbacks.filter((row) =>
  operationIds.includes(row.operation_id),
);
const count = (state) => state.requests.find((row) => row.route === "publish")?.count ?? 0;
report.remote_publish_requests = count(after) - count(before);
assert.equal(report.remote_publish_requests, 3, "Lost response must not cause another POST.");
assert.equal(after.active.artifact_sha256, report.phases.rollback.artifact_sha256);
const listing = spawnSync(
  "docker",
  [
    "compose",
    "exec",
    "-T",
    "-e",
    "MESH_DEMO_ORIGIN=http://127.0.0.1:3000",
    "-e",
    "MESH_DEMO_PASSWORD=MeshDemo2026!",
    "api",
    "ruby",
    "bin/mesh-publish",
    "list",
  ],
  { encoding: "utf8", timeout: 15000, windowsHide: true, maxBuffer: 2 ** 22 },
);
if (listing.error) throw listing.error;
assert.equal(listing.status, 0, "Cannot verify local state after delayed callback.");
const local = JSON.parse(listing.stdout).partners.find((row) => row.id === report.partner_id);
assert.equal(
  local.active_deployment_id,
  report.phases.rollback.id,
  "Delayed callback regressed the local active release.",
);
assert.equal(local.active_sequence, report.phases.rollback.remote_sequence);
report.local_active_after_delayed_callback = {
  deployment_id: local.active_deployment_id,
  sequence: local.active_sequence,
};

report.downloads = [];
for (const phase of ["normal_release", "lost_response", "rollback"]) {
  const row = report.phases[phase];
  const id = phase === "lost_response" ? row.recovered.id : row.id;
  const response = await partner("/artifacts/" + id);
  const reader = response.body.getReader();
  const hash = createHash("sha256");
  let bytes = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.length;
    assert.ok(bytes <= 2_000_000);
    hash.update(value);
  }
  const digest = hash.digest("hex");
  assert.equal(digest, row.artifact_sha256);
  report.downloads.push({ phase, bytes, sha256: digest, private_authenticated_download: true });
}
report.partner_state_after = after;
await writeFile(directory + "/summary.json", JSON.stringify(report, null, 2) + "\n");
console.log(
  JSON.stringify(
    {
      success: true,
      remote_publish_requests: report.remote_publish_requests,
      lost_response_recovered_by_lookup: true,
      verified_artifacts: report.downloads.length,
      report: directory + "/summary.json",
    },
    null,
    2,
  ),
);
