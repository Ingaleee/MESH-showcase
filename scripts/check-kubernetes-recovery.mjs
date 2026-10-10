import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
await readFile("SHOWCASE.md");
const directory = "docs/evidence/publishing-kubernetes";
const binary = path.resolve(".cache/tools/kubectl/kubectl.exe");
const prefix = [
  "--kubeconfig",
  path.resolve(".cache/kubernetes/config"),
  "--context",
  "k3d-mesh-showcase",
  "-n",
  "mesh-showcase",
];
function run(program, args, input) {
  const result = spawnSync(program, args, {
    input,
    encoding: "utf8",
    windowsHide: true,
    timeout: 120000,
    maxBuffer: 2 ** 22,
  });
  if (result.error || result.status !== 0) throw result.error ?? new Error(result.stderr);
  return result.stdout;
}
const kubectl = (args, input) => run(binary, [...prefix, ...args], input);
const docker = (args) => run("docker", args);
const snapshot = () =>
  JSON.parse(kubectl(["get", "pods", "-l", "app=mesh,component=api", "-o", "json"])).items.map(
    (pod) => ({
      name: pod.metadata.name,
      uid: pod.metadata.uid,
      ready: pod.status.conditions?.find((row) => row.type === "Ready")?.status,
      restarts: pod.status.containerStatuses?.[0].restartCount ?? 0,
    }),
  );
async function waitFor(condition, seconds = 45) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    const value = condition();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error("Kubernetes recovery observation timed out.");
}
function http(pod, route) {
  return Number(
    kubectl([
      "exec",
      pod,
      "--",
      "ruby",
      "-rnet/http",
      "-e",
      'puts Net::HTTP.new("127.0.0.1",3000,nil).get("' + route + '").code',
    ]).trim(),
  );
}
const correlation = randomUUID();
async function probe(phase) {
  const source = await readFile("apps/api/script/kubernetes_probe.rb", "utf8");
  const output = kubectl(
    [
      "exec",
      "-i",
      "deployment/mesh-api",
      "--",
      "env",
      "MESH_KUBERNETES_PROBE=true",
      "bundle",
      "exec",
      "rails",
      "runner",
      "-",
      phase,
      correlation,
    ],
    source,
  );
  const line = output.split("\n").find((row) => row.startsWith("MESH_KUBERNETES_REPORT="));
  if (!line) throw new Error("Controlled Ruby probe did not report a result.");
  return JSON.parse(line.slice("MESH_KUBERNETES_REPORT=".length));
}
const report = {
  checked_at: new Date().toISOString(),
  context: "k3d-mesh-showcase",
  success: false,
  scope:
    "One local node, separate databases and private PVC; controlled synthetic events. API liveness/readiness during DB outage and worker drain are measured, not physical HA or production SLO.",
};
try {
  report.api_before = snapshot();
  assert.equal(report.api_before.length, 2);
  assert.ok(report.api_before.every((row) => row.ready === "True"));
  kubectl(["scale", "deployment/mesh-worker", "--replicas=0"]);
  await waitFor(
    () =>
      JSON.parse(kubectl(["get", "pods", "-l", "app=mesh,component=worker", "-o", "json"])).items
        .length === 0,
  );
  report.backlog = await probe("burst");
  assert.equal(report.backlog.events, 50);
  const api = report.api_before[0].name;
  assert.equal(http(api, "/ready"), 200);
  kubectl(["scale", "deployment/mesh-worker", "--replicas=1"]);
  kubectl(["rollout", "status", "deployment/mesh-worker", "--timeout=90s"]);
  report.worker_recovery = await probe("drain");
  assert.deepEqual(report.worker_recovery.effects_per_event, [1]);
  report.database_stopped_at = new Date().toISOString();
  docker(["stop", "mesh-showcase-db-1"]);
  report.api_while_database_down = await waitFor(() => {
    const state = snapshot();
    return state.length === 2 && state.every((row) => row.ready === "False") && state;
  });
  report.http_while_database_down = { ready: http(api, "/ready"), liveness: http(api, "/up") };
  assert.equal(report.http_while_database_down.ready, 503);
  assert.equal(report.http_while_database_down.liveness, 200);
  await new Promise((resolve) => setTimeout(resolve, 15000));
  report.api_after_liveness_cycles = snapshot();
  assert.deepEqual(
    report.api_after_liveness_cycles.map((row) => [row.uid, row.restarts]),
    report.api_before.map((row) => [row.uid, row.restarts]),
  );
  docker(["start", "mesh-showcase-db-1"]);
  report.api_restored = await waitFor(() => {
    const state = snapshot();
    return state.length === 2 && state.every((row) => row.ready === "True") && state;
  }, 90);
  assert.equal(http(api, "/ready"), 200);
  report.success = true;
} catch (error) {
  report.failure = error.message;
  throw error;
} finally {
  docker(["start", "mesh-showcase-db-1"]);
  kubectl(["scale", "deployment/mesh-worker", "--replicas=1"]);
  await writeFile(directory + "/recovery.json", JSON.stringify(report, null, 2) + "\n");
}
console.log(JSON.stringify(report, null, 2));
