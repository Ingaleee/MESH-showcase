import { spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import assert from "node:assert/strict";
const compose = [
  "compose",
  "--env-file",
  ".cache/telemetry/runtime.env",
  "-f",
  "infra/telemetry/compose.yaml",
];
function dc(args) {
  const r = spawnSync("docker", [...compose, ...args], { encoding: "utf8", timeout: 60000 });
  if (r.status !== 0) throw Error(r.stderr);
  return r.stdout;
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function api(port, route, options) {
  const r = await fetch("http://127.0.0.1:" + port + route, {
    ...options,
    signal: AbortSignal.timeout(5000),
  });
  assert.ok(r.ok);
  const text = await r.text();
  return text ? JSON.parse(text) : null;
}
const evidence = process.env.MESH_EVIDENCE_DIR ?? ".cache/acceptance-evidence";
for (const [port, route] of [
  [32091, "/-/ready"],
  [32093, "/-/ready"],
]) {
  let ready = false;
  for (let attempt = 0; attempt < 60; attempt++) {
    try {
      const response = await fetch("http://127.0.0.1:" + port + route, {
        signal: AbortSignal.timeout(2000),
      });
      if (response.ok) {
        ready = true;
        break;
      }
    } catch {}
    await sleep(1000);
  }
  assert.ok(ready, "Telemetry service did not become ready: " + port);
}
let scraped = false;
for (let attempt = 0; attempt < 30; attempt++) {
  const result = await api(
    32091,
    "/api/v1/query?query=" + encodeURIComponent('up{job="mesh-api"}'),
  );
  if (result.data.result.some((row) => row.value[1] === "1")) {
    scraped = true;
    break;
  }
  await sleep(1000);
}
assert.ok(scraped, "A healthy API scrape is required before the retention exercise.");
const name = "MeshRetentionProbe";
const started = new Date();
await api(32093, "/api/v2/alerts", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify([
    {
      labels: { alertname: name, severity: "info" },
      annotations: { summary: "Synthetic retention probe" },
      startsAt: started.toISOString(),
      endsAt: new Date(Date.now() + 60000).toISOString(),
    },
  ]),
});
let receipts;
for (let i = 0; i < 35; i++) {
  try {
    receipts = dc(["exec", "-T", "receiver", "cat", "/data/receipts.jsonl"]);
    if (
      receipts
        .trim()
        .split("\n")
        .map(JSON.parse)
        .some(
          (row) =>
            Date.parse(row.received_at) >= started.getTime() &&
            row.alerts.some((alert) => alert.name === name),
        )
    )
      break;
  } catch {}
  await sleep(1000);
}
assert.ok(
  receipts
    ?.trim()
    .split("\n")
    .map(JSON.parse)
    .some(
      (row) =>
        Date.parse(row.received_at) >= started.getTime() &&
        row.alerts.some((alert) => alert.name === name),
    ),
  "This run must receive a new webhook.",
);
const at = Date.now() / 1000;
const route = "/api/v1/query?query=" + encodeURIComponent('up{job="mesh-api"}') + "&time=" + at;
const before = (await api(32091, route)).data.result;
assert.equal(before.length, 1);
assert.equal(before[0].value[1], "1");
const alertsBefore = await api(32093, "/api/v2/alerts");
assert.ok(alertsBefore.some((row) => row.labels.alertname === name));
const silence = await api(32093, "/api/v2/silences", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    matchers: [{ name: "alertname", value: name, isRegex: false }],
    startsAt: new Date().toISOString(),
    endsAt: new Date(Date.now() + 300000).toISOString(),
    createdBy: "synthetic retention drill",
    comment: "Verify durable Alertmanager silences",
  }),
});
dc(["restart", "prometheus", "alertmanager", "receiver"]);
for (let i = 0; i < 20; i++) {
  try {
    await api(32091, "/api/v1/query?query=1");
    break;
  } catch {
    await sleep(1000);
  }
}
const after = (await api(32091, route)).data.result;
assert.deepEqual(after, before, "Historic scrape at a fixed instant was lost.");
const restoredSilence = await api(32093, "/api/v2/silence/" + silence.silenceID);
assert.equal(restoredSilence.status.state, "active");
await api(32093, "/api/v2/silence/" + silence.silenceID, { method: "DELETE" });
const afterReceipts = dc(["exec", "-T", "receiver", "cat", "/data/receipts.jsonl"]);
assert.ok(afterReceipts.startsWith(receipts), "Delivered receiver history was lost.");
await mkdir(evidence, { recursive: true });
await writeFile(
  evidence + "/telemetry-retention.json",
  JSON.stringify(
    {
      checked_at: new Date().toISOString(),
      environment:
        process.env.GITHUB_ACTIONS === "true"
          ? "GitHub hosted Ubuntu telemetry"
          : "isolated Docker Desktop telemetry",
      historic_scrape_preserved: true,
      silence_preserved: true,
      active_alert_policy:
        "Alerts are resent by Prometheus, not persisted as an active-alert snapshot.",
      receipt_history_preserved: true,
      prometheus_retention: "7d / 512MB, whichever limit is reached first",
      alert_retention: "120h",
      receipt_budget_bytes: 16777216,
      sample: before,
      scope: "Process restart on the same host; no offsite durability claim.",
    },
    null,
    2,
  ) + "\n",
);
console.log(
  "Historic sample, Alertmanager silence and receiver receipts survived all three process restarts.",
);
