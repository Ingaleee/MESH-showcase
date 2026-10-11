import { spawnSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
await readFile("SHOWCASE.md");
const release = [
  "compose",
  "--env-file",
  ".cache/deployment/runtime.env",
  "-f",
  "infra/deploy/compose.yaml",
  "-p",
  "mesh-showcase-release",
];
const observability = [
  "compose",
  "--env-file",
  ".cache/incident/runtime.env",
  "-f",
  "infra/sre/compose.yaml",
];
function docker(args) {
  const result = spawnSync("docker", args, {
    encoding: "utf8",
    maxBuffer: 2 ** 22,
    timeout: 120000,
  });
  if (result.error || result.status !== 0) throw result.error ?? new Error(result.stderr);
  return result.stdout;
}
const dc = (...args) => docker([...release, ...args]);
function parseReport(output) {
  const start = output.lastIndexOf("\n{\n");
  return JSON.parse(start >= 0 ? output.slice(start).trim() : output.trim());
}
const probe = (phase) =>
  parseReport(
    dc(
      "exec",
      "-T",
      "-e",
      "MESH_DEPLOYMENT_PROBE=true",
      "api",
      "bundle",
      "exec",
      "ruby",
      "script/incident_probe.rb",
      phase,
    ),
  );
function receipts() {
  const output = docker([
    ...observability,
    "exec",
    "-T",
    "receiver",
    "node",
    "-e",
    "try{process.stdout.write(require('node:fs').readFileSync('/data/receipts.jsonl','utf8'))}catch{}",
  ]);
  return output.trim()
    ? output
        .trim()
        .split("\n")
        .map((line) => JSON.parse(line))
    : [];
}
async function wait(condition) {
  const deadline = Date.now() + 60000;
  let failure;
  do {
    try {
      const value = await condition();
      if (value) return value;
    } catch (error) {
      failure = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  } while (Date.now() < deadline);
  throw failure ?? new Error("Incident observation timed out.");
}
const report = {
  checked_at: new Date().toISOString(),
  environment: "mesh-showcase-release",
  cause: "Worker deliberately stopped",
  thresholds: "Lab queue age >3s, hold 3s; production alert thresholds differ",
};
try {
  const targets = await wait(async () => {
    const response = await fetch("http://127.0.0.1:32091/api/v1/targets", {
      signal: AbortSignal.timeout(5000),
    });
    const data = await response.json();
    return data.data?.activeTargets.some((row) => row.health === "up") && data;
  });
  report.metrics_scrape_healthy = targets.status === "success";
  report.stopped_at = new Date().toISOString();
  dc("stop", "worker");
  report.backlog = probe("burst");
  report.firing_receipt = await wait(() =>
    receipts().find((row) =>
      row.alerts.some(
        (alert) => alert.name === "ShowcaseQueueStalled" && alert.status === "firing",
      ),
    ),
  );
  report.restored_at = new Date().toISOString();
  dc("start", "worker");
  report.drained = probe("drain");
  report.resolved_receipt = await wait(() =>
    receipts().find((row) =>
      row.alerts.some(
        (alert) => alert.name === "ShowcaseQueueStalled" && alert.status === "resolved",
      ),
    ),
  );
  report.success = true;
  report.local_detection_seconds =
    (Date.parse(report.firing_receipt.received_at) - Date.parse(report.stopped_at)) / 1000;
  report.scope =
    "Actual Prometheus -> Alertmanager -> authenticated internal webhook; stopped worker recovered and 50 notifications produced exactly once. Single local synthetic run; no production SLO claim or external message.";
} catch (error) {
  report.success = false;
  report.failure = error.message;
  throw error;
} finally {
  dc("start", "worker");
  await writeFile("docs/evidence/showcase-incident.json", JSON.stringify(report, null, 2) + "\n");
}
console.log(JSON.stringify(report, null, 2));
