import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";

async function read(url) {
  const response = await fetch(url);
  assert.equal(response.status, 200, `Unexpected response from ${url}`);
  return response.json();
}

const prometheus = process.env.MESH_PROMETHEUS_URL || "http://localhost:32090";
const jaeger = process.env.MESH_JAEGER_URL || "http://localhost:32686";
const targets = await read(`${prometheus}/api/v1/targets`);
const apiTarget = targets.data.activeTargets.find((target) => target.labels.job === "mesh");
assert.ok(apiTarget, "MESH scrape target is missing.");
assert.equal(apiTarget.health, "up");
const services = await read(`${jaeger}/api/v3/services`);
assert.ok(services.services.includes("mesh-api"));
const operations = await read(`${jaeger}/api/v3/operations?service=mesh-api`);
assert.ok(operations.operations.some((operation) => operation.spanKind === "server"));
assert.ok(operations.operations.some((operation) => operation.name === "mesh.event.consume"));
const query = new URLSearchParams({
  "query.service_name": "mesh-api",
  "query.num_traces": "5",
  "query.start_time_min": new Date(Date.now() - 3_600_000).toISOString(),
  "query.start_time_max": new Date().toISOString(),
});
const traces = await read(`${jaeger}/api/v3/traces?${query}`);
const spans = traces.result.resourceSpans.flatMap((resource) =>
  resource.scopeSpans.flatMap((scope) => scope.spans),
);
assert.ok(spans.length > 0, "Recent spans have not reached the collector.");
const result = {
  timestamp: new Date().toISOString(),
  prometheus_target: { job: apiTarget.labels.job, health: apiTarget.health },
  jaeger_service: "mesh-api",
  observed_operations: operations.operations.map(({ name, spanKind }) => ({ name, spanKind })),
  recent_span_count: spans.length,
  scope:
    "Live local scrape and trace ingestion; retention, alert delivery and uptime are not tested.",
};
await writeFile("docs/evidence/observability.json", JSON.stringify(result, null, 2) + "\n");
console.log(`MESH metrics are up; Jaeger returned ${spans.length} recent spans.`);
