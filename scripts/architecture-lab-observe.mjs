import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { request as httpRequest } from "node:http";

const state = JSON.parse(await readFile(".cache/architecture-lab/run.json", "utf8"));
const phase = process.argv[2];
const request = (path) =>
  new Promise((resolve, reject) => {
    const outgoing = httpRequest(
      `http://127.0.0.1:3214${path}`,
      {
        headers: { Host: "mesh.example.test", Authorization: `Bearer ${state.metrics}` },
      },
      (incoming) => {
        const chunks = [];
        incoming.on("data", (chunk) => chunks.push(chunk));
        incoming.on("error", reject);
        incoming.on("end", () =>
          resolve({ status: incoming.statusCode, body: Buffer.concat(chunks).toString("utf8") }),
        );
      },
    );
    outgoing.setTimeout(6000, () => outgoing.destroy(new Error("Probe timed out")));
    outgoing.on("error", reject);
    outgoing.end();
  });
const prometheus = async (path) => {
  const response = await fetch(`http://127.0.0.1:3215/api/v1/${path}`, {
    signal: AbortSignal.timeout(6000),
  });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.status, "success");
  return result.data;
};
const wait = async (condition, timeout = 45000) => {
  const deadline = Date.now() + timeout;
  let lastError;
  do {
    try {
      if (await condition()) return;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  } while (Date.now() < deadline);
  throw lastError ?? new Error(`Timed out waiting for ${phase}`);
};
if (phase === "boot") {
  await wait(async () => (await request("/ready")).status === 200);
  assert.equal((await request("/api/v1/projects?limit=12")).status, 200);
  await wait(async () =>
    (await prometheus("targets")).activeTargets.some((target) => target.health === "up"),
  );
} else if (["backlog", "poison", "drained"].includes(phase)) {
  const alertName = phase === "backlog" ? "LabQueueWait" : "LabPoisonEvent";
  await wait(async () => {
    const alerts = (await prometheus("alerts")).alerts;
    return phase === "drained"
      ? !alerts.some((alert) => alert.labels.alertname === "LabQueueWait")
      : alerts.some((alert) => alert.labels.alertname === alertName && alert.state === "firing");
  });
  const metrics = await request("/internal/metrics");
  assert.equal(metrics.status, 200);
  assert.match(metrics.body, /mesh_queue_up 1/);
  assert.equal((await request("/ready")).status, 200);
  const report = {
    checkedAt: new Date().toISOString(),
    phase,
    metrics: metrics.body,
    alerts: (await prometheus("alerts")).alerts,
    applicationReady: 200,
    scope:
      "Real Prometheus scrape and rule evaluation. Lab rules use 2-second thresholds/3-second hold times; production uses longer windows. No Alertmanager delivery is claimed.",
  };
  await writeFile(
    `docs/evidence/showcase-architecture-lab/prometheus-${phase}.json`,
    JSON.stringify(report, null, 2) + "\n",
  );
} else if (phase === "timeline") {
  const end = Date.now() / 1000;
  const queries = [
    "mesh_queue_ready",
    "mesh_queue_workers",
    "mesh_queue_failed",
    "mesh_outbox_failed",
  ];
  const series = {};
  for (const query of queries) {
    series[query] = await prometheus(
      `query_range?query=${encodeURIComponent(query)}&start=${end - 900}&end=${end}&step=1`,
    );
  }
  const events = series.mesh_queue_ready.result.find((row) => row.metric.queue === "events");
  const peak = events?.values.find(([, value]) => Number(value) >= 50);
  assert.ok(peak);
  assert.ok(events.values.some(([timestamp, value]) => timestamp > peak[0] && Number(value) === 0));
  await writeFile(
    "docs/evidence/showcase-architecture-lab/queue-timeline.json",
    JSON.stringify({ checkedAt: new Date().toISOString(), stepSeconds: 1, series }, null, 2) + "\n",
  );
} else {
  throw new Error("Unknown observation phase");
}
console.log(`Architecture lab observation passed: ${phase}`);
