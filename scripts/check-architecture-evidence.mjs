import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

const root = "docs/evidence/showcase-architecture-lab";
const names = [
  "dataset",
  "queries-before",
  "queries-after",
  "indexes",
  "environment",
  "load",
  "queue-backlog",
  "queue-drained",
  "queue-outage",
  "queue-poison",
  "prometheus-backlog",
  "prometheus-drained",
  "prometheus-poison",
  "queue-timeline",
  "backup",
  "restore-copy",
  "restore-verified",
  "restored-queue",
  "recovery-time",
];
const contents = await Promise.all(
  names.map(async (name) => [name, await readFile(`${root}/${name}.json`)]),
);
const reports = Object.fromEntries(
  contents.map(([name, bytes]) => [
    name,
    JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")),
  ]),
);
assert.equal(reports.dataset.projects, 100001);
assert.equal(reports.dataset.profiles, 20000);
assert.equal(reports.dataset.proposals, 200001);
const before = reports["queries-before"].cases;
const after = reports["queries-after"].cases;
assert.deepEqual(
  before.map(({ name, record_ids }) => [name, record_ids]),
  after.map(({ name, record_ids }) => [name, record_ids]),
);
assert.ok(
  after.every((row) => row.record_ids.length > 0 && row.sql_count.every((count) => count === 2)),
);
assert.equal(after.length, 5);
assert.match(
  JSON.stringify(after.find((row) => row.name === "project_search").plan),
  /project_title_trigram/,
);
const deep = after.find((row) => row.name === "deep_feed");
assert.ok(deep.plan[0].Plan["Shared Hit Blocks"] < 100);
assert.match(deep.sql, /\(created_at, id\) </);
for (const metric of Object.values(reports.load.metrics)) {
  if (metric.thresholds) assert.ok(Object.values(metric.thresholds).every(({ ok }) => ok));
}
assert.equal(reports.load.metrics.http_req_failed.values.rate, 0);
assert.equal(reports.load.metrics.dropped_iterations.values.count, 0);
assert.ok(reports.load.metrics.iterations.values.count >= 2400);
assert.equal(reports["queue-drained"].processed, 50);
assert.deepEqual(reports["queue-drained"].effects_per_event, [1]);
assert.equal(reports["queue-drained"].workers, 3);
assert.equal(reports["queue-outage"].unavailable_snapshot.available, false);
assert.equal(reports["queue-outage"].state_after, "processed");
assert.equal(reports["queue-poison"].failures, 5);
assert.equal(reports["queue-poison"].state, "failed");
assert.equal(reports["queue-poison"].notifications, 0);
assert.ok(
  reports["prometheus-backlog"].alerts.some(
    (alert) => alert.labels.alertname === "LabQueueWait" && alert.state === "firing",
  ),
);
assert.ok(
  !reports["prometheus-drained"].alerts.some((alert) => alert.labels.alertname === "LabQueueWait"),
);
assert.ok(
  reports["prometheus-poison"].alerts.some(
    (alert) => alert.labels.alertname === "LabPoisonEvent" && alert.state === "firing",
  ),
);
const restore = reports["restore-verified"];
assert.equal(restore.counts_match, true);
assert.equal(restore.blobs_verified, 2);
assert.deepEqual(restore.integrity_probes, { missing: true, corrupted: true });
assert.equal(restore.immutable_trigger_verified, true);
assert.equal(restore.submission_manifest_verified, true);
assert.ok(restore.authenticated_private_downloads.every((row) => row.status === 200));
assert.equal(reports["restored-queue"].notifications, 1);
assert.equal(reports["restored-queue"].fresh_queue, true);
assert.equal(reports["restored-queue"].payouts_disabled, true);
assert.equal(reports["restored-queue"].claim_cleared, true);
assert.ok(reports["restored-queue"].attempts >= 2);
assert.equal(reports.backup.dump_sha256, reports["restore-copy"].dump_sha256);
const summary = {
  checkedAt: new Date().toISOString(),
  dataset: reports.dataset,
  queryTimings: after.map((row) => ({
    name: row.name,
    beforeP50Ms: before.find((previous) => previous.name === row.name).p50_ms,
    afterP50Ms: row.p50_ms,
    afterP95Ms: row.p95_ms,
    sqlCount: row.sql_count,
  })),
  httpRequests: reports.load.metrics.http_reqs.values.count,
  iterations: reports.load.metrics.iterations.values.count,
  httpP95Ms: reports.load.metrics.http_req_duration.values["p(95)"],
  routeP95Ms: Object.fromEntries(
    Object.entries(reports.load.metrics)
      .filter(([name]) => name.startsWith("http_req_duration{route:"))
      .map(([name, value]) => [name, value.values["p(95)"]]),
  ),
  indexBytes: reports.indexes.indexes.reduce((sum, row) => sum + Number(row.bytes), 0),
  dumpBytes: reports.backup.dump_bytes,
  restoredFileBytes: reports["restore-copy"].total_file_bytes,
  localRecoverySeconds: reports["recovery-time"].localRecoverySeconds,
  artifacts: Object.fromEntries(
    contents.map(([name, bytes]) => [
      `${name}.json`,
      createHash("sha256").update(bytes).digest("hex"),
    ]),
  ),
  scope:
    "Executed local diagnostic experiments on synthetic data. Hashes detect drift relative to this manifest; they are not a signed attestation. RSpec/security and earlier financial restore evidence are separate. No production capacity, PITR, S3, multi-region or SLA claim.",
};
await writeFile(`${root}/summary.json`, JSON.stringify(summary, null, 2) + "\n");
console.log(
  `Architecture evidence agrees: ${summary.httpRequests} HTTP requests, 50 recovered events, DB + private files restored.`,
);
