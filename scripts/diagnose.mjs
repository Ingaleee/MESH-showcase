import { spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { performance } from "node:perf_hooks";

const project = process.env.MESH_DIAGNOSTIC_PROJECT ?? "mesh-showcase";
if (!["mesh-showcase", "mesh-showcase-release"].includes(project))
  throw new Error("Select only an isolated showcase Compose project.");
const origin = new URL(process.env.MESH_DIAGNOSTIC_ORIGIN ?? "http://localhost:3200");
if (
  !["http:", "https:"].includes(origin.protocol) ||
  !["localhost", "127.0.0.1", "[::1]"].includes(origin.hostname) ||
  origin.username ||
  origin.password ||
  origin.pathname !== "/" ||
  origin.search ||
  origin.hash
)
  throw new Error("Diagnostics accept only a credential-free loopback origin.");

const report = {
  checked_at: new Date().toISOString(),
  project,
  origin: origin.origin,
  probes: {},
  scope:
    "Read-only local triage: HTTP readiness, container state, bounded queue snapshot and simulator health. No log bodies, environment secrets, mutations or external provider calls.",
};
function command(args, timeout = 15_000) {
  const result = spawnSync("docker", args, {
    encoding: "utf8",
    timeout,
    maxBuffer: 2 ** 20,
    windowsHide: true,
  });
  if (result.error || result.status !== 0)
    throw new Error(result.error?.code ?? "docker-command-failed");
  return result.stdout;
}
async function probe(name, action) {
  const start = performance.now();
  try {
    report.probes[name] = { ok: true, ...(await action()) };
  } catch (error) {
    // Error messages can contain credential-bearing URLs; preserve only the class.
    report.probes[name] = { ok: false, error_class: error.name };
  }
  report.probes[name].elapsed_ms = Math.round(performance.now() - start);
}
async function http(endpoint, expected) {
  const response = await fetch(new URL(endpoint, origin), {
    redirect: "error",
    signal: AbortSignal.timeout(5_000),
  });
  if (response.status !== 200) {
    await response.body?.cancel();
    return { ok: false, status: response.status };
  }
  if (!expected) {
    await response.body?.cancel();
    return { status: response.status };
  }
  const reader = response.body.getReader();
  let bytes = 0;
  const chunks = [];
  try {
    while (true) {
      const row = await reader.read();
      if (row.done) break;
      bytes += row.value.length;
      if (bytes > 16_384) throw new Error("Diagnostic response exceeds its budget.");
      chunks.push(Buffer.from(row.value));
    }
  } finally {
    await reader.cancel();
  }
  const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  return { ok: expected(body), status: response.status };
}
await probe("frontend", () => http("/"));
await probe("database_readiness", () => http("/ready", (body) => body.status === "ready"));
await probe("session_contract", () =>
  http("/api/v1/session", (body) => typeof body.csrf_token === "string"),
);
let api;
await probe("containers", () => {
  const ids = command(["ps", "-a", "-q", "--filter", `label=com.docker.compose.project=${project}`])
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (!ids.length) throw new Error("Showcase containers are absent.");
  const rows = JSON.parse(command(["inspect", ...ids]));
  const services = rows
    .map((row) => ({
      service: row.Config.Labels["com.docker.compose.service"],
      running: row.State.Running,
      health: row.State.Health?.Status ?? null,
      oom_killed: row.State.OOMKilled,
      image: row.Image,
    }))
    .filter((row) =>
      ["api", "web", "worker", "dispatcher", "db", "gateway", "scanner", "edge"].includes(
        row.service,
      ),
    );
  api = rows.find(
    (row) => row.Config.Labels["com.docker.compose.service"] === "api" && row.State.Running,
  )?.Id;
  const required = ["api", "web", "worker", "dispatcher", "db", "gateway", "scanner", "edge"];
  return {
    ok: required.every((name) =>
      services.some(
        (row) => row.service === name && row.running && (!row.health || row.health === "healthy"),
      ),
    ),
    services,
  };
});
await probe("queue", () => {
  if (!api) throw new Error("API unavailable for internal queue snapshot.");
  const marker = "MESH_DIAGNOSTIC_JSON=";
  const output = command(
    [
      "exec",
      api,
      "bundle",
      "exec",
      "rails",
      "runner",
      `puts "${marker}" + JSON.generate(QueueMetrics.snapshot)`,
    ],
    45_000,
  );
  const line = output.split("\n").find((row) => row.startsWith(marker));
  if (!line) throw new Error("Queue snapshot is absent.");
  const snapshot = JSON.parse(line.slice(marker.length));
  const rows = snapshot.rows ?? [];
  const ready = rows
    .filter((row) => row.state === "ready")
    .reduce((sum, row) => sum + Number(row.count), 0);
  return {
    ok: snapshot.available === true && snapshot.workers > 0,
    available: snapshot.available,
    workers: snapshot.workers ?? null,
    ready,
    failed: rows
      .filter((row) => row.state === "failed")
      .reduce((sum, row) => sum + Number(row.count), 0),
    oldest_ready_seconds: Math.max(
      0,
      ...rows.filter((row) => row.state === "ready").map((row) => Number(row.oldest_seconds)),
    ),
  };
});
await probe("gateway", () => {
  if (!api) throw new Error("API unavailable for internal simulator probe.");
  const result = JSON.parse(
    command([
      "exec",
      api,
      "curl",
      "--silent",
      "--show-error",
      "--fail",
      "--max-time",
      "4",
      "http://gateway:3102/health",
    ]),
  );
  return { ok: result.ready === true, simulator_only: true };
});
report.success = Object.values(report.probes).every((row) => row.ok);
const directory = path.resolve(process.env.MESH_EVIDENCE_DIR ?? "docs/evidence/showcase-final");
await mkdir(directory, { recursive: true });
await writeFile(path.join(directory, "diagnostic.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report, null, 2));
if (!report.success) process.exitCode = 1;
