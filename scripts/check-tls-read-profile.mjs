import https from "node:https";
import { spawnSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
const state = path.resolve(process.env.MESH_DEPLOYMENT_STATE ?? ".cache/deployment");
const secrets = await readFile(path.join(state, "secrets.env"), "utf8");
const origin = /^MESH_PUBLIC_ORIGIN=(.+)$/m.exec(secrets)?.[1];
assert.match(origin, /^https:\/\/localhost:\d+$/);
const agent = new https.Agent({
  keepAlive: true,
  ca: await readFile(path.join(state, "root.crt")),
});
const config = {
  arrival_rate_per_second: 10,
  duration_seconds: 30,
  maximum_in_flight: 8,
  maximum_unexpected_errors: 0,
  maximum_read_p95_ms: 750,
};
const samples = [];
async function request(route) {
  const started = performance.now();
  return new Promise((resolve) => {
    const req = https.get(origin + route, { agent }, (response) => {
      response.resume();
      response.on("end", () =>
        resolve({ route, status: response.statusCode, elapsed_ms: performance.now() - started }),
      );
    });
    req.setTimeout(5000, () => req.destroy(Error("request deadline")));
    req.on("error", (error) =>
      resolve({ route, status: 0, error: error.message, elapsed_ms: performance.now() - started }),
    );
  });
}
const routes = [
  "/api/v1/projects?limit=20",
  "/api/v1/creators?limit=20",
  "/api/v1/session",
  "/ready",
];
for (let i = 0; i < 12; i++) assert.equal((await request(routes[i % routes.length])).status, 200);
const inFlight = new Set();
const began = performance.now();
let rejected_arrivals = 0;
for (let i = 0; i < config.duration_seconds * config.arrival_rate_per_second; i++) {
  const target = began + i * (1000 / config.arrival_rate_per_second);
  await new Promise((resolve) => setTimeout(resolve, Math.max(0, target - performance.now())));
  if (inFlight.size >= config.maximum_in_flight) {
    rejected_arrivals++;
    continue;
  }
  const promise = request(routes[i % routes.length])
    .then((sample) => samples.push(sample))
    .finally(() => inFlight.delete(promise));
  inFlight.add(promise);
}
await Promise.all(inFlight);
agent.destroy();
const elapsed = (performance.now() - began) / 1000;
const latencies = samples.map((s) => s.elapsed_ms).sort((a, b) => a - b);
const percentile = (p) =>
  latencies[Math.min(latencies.length - 1, Math.ceil(latencies.length * p) - 1)];
const errors = samples.filter((s) => s.status !== 200);
const runtime = spawnSync("docker", ["stats", "--no-stream", "--format", "{{json .}}"], {
  encoding: "utf8",
  timeout: 15000,
});
const stats = runtime.stdout
  .split("\n")
  .filter((line) => line.includes("mesh-showcase-release"))
  .map(JSON.parse);
const report = {
  checked_at: new Date().toISOString(),
  config,
  elapsed_seconds: elapsed,
  achieved_requests_per_second: samples.length / elapsed,
  requests: samples.length,
  rejected_arrivals,
  errors: errors.length,
  p50_ms: percentile(0.5),
  p95_ms: percentile(0.95),
  p99_ms: percentile(0.99),
  containers: stats,
  samples,
  scope:
    "Current loopback TLS release, existing synthetic business dataset, bounded arrival experiment on hosted Ubuntu. Reads only; no mixed-load capacity or sustained production SLO claim.",
};
await writeFile(
  path.join(process.env.MESH_EVIDENCE_DIR, "tls-read-profile.json"),
  JSON.stringify(report, null, 2) + "\n",
);
assert.equal(errors.length, config.maximum_unexpected_errors);
assert.equal(rejected_arrivals, 0);
assert.ok(
  report.p95_ms <= config.maximum_read_p95_ms,
  "Declared lab latency threshold was exceeded.",
);
console.log(
  JSON.stringify({
    requests: report.requests,
    p95_ms: report.p95_ms,
    p99_ms: report.p99_ms,
    errors: report.errors,
  }),
);
