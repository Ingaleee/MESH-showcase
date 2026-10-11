import { spawnSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import assert from "node:assert/strict";
await readFile("SHOWCASE.md");
const directory = process.env.MESH_EVIDENCE_DIR ?? "docs/evidence/publishing-incident";
await mkdir(directory, { recursive: true });
function docker(args) {
  const result = spawnSync("docker", args, {
    encoding: "utf8",
    timeout: 120000,
    maxBuffer: 2 ** 22,
    windowsHide: true,
  });
  if (result.error || result.status !== 0) throw result.error ?? new Error(result.stderr);
  return result.stdout;
}
const telemetry = [
  "compose",
  "--env-file",
  ".cache/telemetry/runtime.env",
  "-f",
  "infra/telemetry/compose.yaml",
];
function probe(phase) {
  const text = docker([
    "compose",
    "exec",
    "-T",
    "-e",
    "MESH_SHOWCASE_INCIDENT=true",
    "api",
    "bundle",
    "exec",
    "ruby",
    "script/showcase_incident.rb",
    phase,
  ]);
  const line = text.split("\n").find((row) => row.startsWith("MESH_INCIDENT_REPORT="));
  if (!line) throw new Error("Incident probe did not report a result.");
  return JSON.parse(line.slice("MESH_INCIDENT_REPORT=".length));
}
function receipts() {
  const output = docker([
    ...telemetry,
    "exec",
    "-T",
    "receiver",
    "node",
    "-e",
    "try{process.stdout.write(require('node:fs').readFileSync('/data/receipts.jsonl','utf8'))}catch{}",
  ]);
  return output.trim() ? output.trim().split("\n").map(JSON.parse) : [];
}
async function waitFor(condition) {
  const deadline = Date.now() + 90000;
  while (Date.now() < deadline) {
    const result = await condition();
    if (result) return result;
    await new Promise((resolve) => setTimeout(resolve, 1500));
  }
  throw new Error("Live incident observation timed out.");
}
const report = {
  checked_at: new Date().toISOString(),
  environment: "mesh-showcase development",
  lab_threshold: "queue age >10s for 5s; 5s scrapes",
  success: false,
};
const receiptMatches = (status) =>
  receipts().find(
    (row) =>
      Date.parse(row.received_at) >= Date.parse(report.stopped_at) &&
      row.alerts.some((alert) => alert.name === "ShowcaseQueueStalled" && alert.status === status),
  );
try {
  await waitFor(async () => {
    const target = await (await fetch("http://localhost:32091/api/v1/targets")).json();
    return target.data?.activeTargets.some((row) => row.health === "up");
  });
  report.stopped_at = new Date().toISOString();
  docker(["compose", "stop", "worker"]);
  report.backlog = probe("burst");
  report.http_while_worker_stopped = [];
  for (const route of ["/", "/ready", "/api/v1/session", "/api/v1/projects"]) {
    const response = await fetch("http://localhost:3200" + route, {
      signal: AbortSignal.timeout(10000),
    });
    report.http_while_worker_stopped.push({ route, status: response.status });
    assert.equal(response.status, 200);
    await response.body?.cancel();
  }
  report.firing_receipt = await waitFor(() => receiptMatches("firing"));
  docker(["compose", "start", "worker"]);
  report.drained = probe("drain");
  assert.equal(report.drained.events, 50);
  assert.deepEqual(report.drained.effects_per_event, [1]);
  assert.equal(report.drained.replay_observations_added, 0);
  report.resolved_receipt = await waitFor(() => receiptMatches("resolved"));
  report.detection_seconds =
    (Date.parse(report.firing_receipt.received_at) - Date.parse(report.stopped_at)) / 1000;
  const expressions = [
    "histogram_quantile(0.95, max by (le) (rate(mesh_notification_delivery_seconds_bucket[5m])))",
    "sum(mesh_http_request_seconds_count)",
  ];
  report.prometheus_observations = [];
  for (const query of expressions) {
    const data = await (
      await fetch("http://localhost:32091/api/v1/query?query=" + encodeURIComponent(query))
    ).json();
    assert.equal(data.status, "success");
    assert.ok(data.data.result.length);
    report.prometheus_observations.push({ query, result: data.data.result });
  }
  report.success = true;
  report.scope =
    "Real local worker outage, HTTP availability, signed internal alert delivery/resolution, 50 once-only DB effects and durable latency observations. Lab thresholds, shared host; WebSocket receipt and production SLO are separate.";
} catch (error) {
  report.failure = error.message;
  throw error;
} finally {
  docker(["compose", "start", "worker"]);
  await writeFile(directory + "/summary.json", JSON.stringify(report, null, 2) + "\n");
}
console.log(JSON.stringify(report, null, 2));
