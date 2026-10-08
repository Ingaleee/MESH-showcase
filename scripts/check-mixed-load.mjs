import https from "node:https";
import { spawn, spawnSync, execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import path from "node:path";
import assert from "node:assert/strict";

assert.equal(
  process.env.GITHUB_ACTIONS,
  "true",
  "Mixed saturation exercise requires the isolated hosted VM.",
);
const state = path.resolve(process.env.MESH_DEPLOYMENT_STATE ?? ".cache/deployment");
const secrets = await readFile(path.join(state, "secrets.env"), "utf8");
const origin = /^MESH_PUBLIC_ORIGIN=(.+)$/m.exec(secrets)?.[1];
assert.match(origin, /^https:\/\/localhost:\d+$/);
const compose = [
  "compose",
  "--env-file",
  path.join(state, "runtime.env"),
  "-f",
  "infra/deploy/compose.yaml",
  "-p",
  "mesh-showcase-release",
];
const evidence = process.env.MESH_EVIDENCE_DIR;
const config = {
  seeded_projects: 10000,
  mix: { read: 0.5, command: 0.25, replay: 0.25 },
  max_in_flight: 40,
  phases: [
    { name: "baseline", rate: 5, seconds: 30 },
    { name: "ramp20", rate: 20, seconds: 15 },
    { name: "ramp60", rate: 60, seconds: 15 },
    { name: "ramp120", rate: 120, seconds: 15 },
    { name: "controlled_db_contention", rate: 60, seconds: 10 },
  ],
  baseline_max_p95_ms: 1500,
  recovery_seconds: 60,
  backlog_seconds: 120,
};
function dc(args) {
  const result = spawnSync("docker", [...compose, ...args], {
    encoding: "utf8",
    timeout: 90000,
    maxBuffer: 8 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) throw result.error ?? Error(result.stderr.slice(-800));
  return result.stdout.trim();
}
function probe(action) {
  return JSON.parse(
    dc([
      "exec",
      "-T",
      "-e",
      "GITHUB_ACTIONS=true",
      "-e",
      "MESH_LOAD_PROBE=true",
      "api",
      "bundle",
      "exec",
      "ruby",
      "script/mixed_load_probe.rb",
      action,
    ])
      .split("\n")
      .at(-1),
  );
}
const fixture = probe("prepare");
const agent = new https.Agent({
  keepAlive: true,
  maxSockets: 48,
  ca: await readFile(path.join(state, "root.crt")),
});
let cookie = "",
  csrf = "";
function request(route, method = "GET", body, key) {
  const start = performance.now();
  return new Promise((resolve) => {
    const bytes = body ? Buffer.from(JSON.stringify(body)) : null;
    const req = https.request(
      origin + route,
      {
        method,
        agent,
        headers: {
          ...(cookie ? { Cookie: cookie } : {}),
          ...(csrf ? { "X-CSRF-Token": csrf } : {}),
          ...(bytes ? { "content-type": "application/json", "content-length": bytes.length } : {}),
          ...(key ? { "Idempotency-Key": key } : {}),
        },
      },
      (res) => {
        let text = "";
        res.on("data", (chunk) => {
          if (text.length < 256000) text += chunk;
        });
        res.on("end", () => {
          let data;
          try {
            data = JSON.parse(text);
          } catch {
            data = {};
          }
          resolve({
            status: res.statusCode,
            code: data.code,
            id: data.id,
            data,
            cookies: res.headers["set-cookie"],
            elapsed_ms: performance.now() - start,
          });
        });
      },
    );
    req.setTimeout(12000, () => req.destroy(Error("request deadline")));
    req.on("error", (error) =>
      resolve({ status: 0, error: error.message, elapsed_ms: performance.now() - start }),
    );
    if (bytes) req.write(bytes);
    req.end();
  });
}
let session = await request("/api/v1/session");
assert.equal(session.status, 200);
cookie = session.cookies.map((value) => value.split(";")[0]).join("; ");
csrf = session.data.csrf_token;
session = await request("/api/v1/session", "POST", {
  session: { email: fixture.email, password: fixture.password },
});
assert.equal(session.status, 200);
cookie = session.cookies.map((value) => value.split(";")[0]).join("; ");
csrf = session.data.csrf_token;
const samples = [],
  telemetry = [],
  commands = new Map();
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const exec = promisify(execFile);
let sampling = null;
const monitor = setInterval(() => {
  if (sampling) return;
  sampling = (async () => {
    try {
      const stats = await exec("docker", ["stats", "--no-stream", "--format", "{{json .}}"], {
        encoding: "utf8",
        timeout: 10000,
      });
      const pg = await exec(
        "docker",
        [
          ...compose,
          "exec",
          "-T",
          "db",
          "psql",
          "-U",
          "mesh_owner",
          "-d",
          "mesh_production",
          "-Atc",
          "SELECT json_build_object('connections',count(*),'active',count(*) FILTER (WHERE state='active'),'lock_waiters',count(*) FILTER (WHERE wait_event_type='Lock'),'max_connections',current_setting('max_connections')) FROM pg_stat_activity",
        ],
        { encoding: "utf8", timeout: 15000 },
      );
      telemetry.push({
        at: new Date().toISOString(),
        pg: JSON.parse(pg.stdout),
        containers: stats.stdout
          .split("\n")
          .filter((line) => line.includes("mesh-showcase-release"))
          .map(JSON.parse),
      });
    } catch (error) {
      telemetry.push({ at: new Date().toISOString(), error: error.message });
    } finally {
      sampling = null;
    }
  })();
}, 3000);
const summaries = [];
try {
  for (const phase of config.phases) {
    let blocker;
    if (phase.name === "controlled_db_contention") {
      blocker = spawn("docker", [
        ...compose,
        "exec",
        "-T",
        "-e",
        "GITHUB_ACTIONS=true",
        "-e",
        "MESH_LOAD_PROBE=true",
        "api",
        "bundle",
        "exec",
        "ruby",
        "script/mixed_load_probe.rb",
        "contend",
      ]);
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(Error("contention barrier timeout")), 60000);
        blocker.stdout.on("data", (chunk) => {
          if (chunk.toString().includes("CONTENTION_READY")) {
            clearTimeout(timer);
            resolve();
          }
        });
        blocker.once("exit", (code) => {
          if (code) reject(Error("contention probe failed"));
        });
      });
    }
    const inFlight = new Set(),
      own = [];
    let dropped = 0;
    const began = performance.now();
    for (let i = 0; i < phase.rate * phase.seconds; i++) {
      await sleep(Math.max(0, began + (i * 1000) / phase.rate - performance.now()));
      if (inFlight.size >= config.max_in_flight) {
        dropped++;
        continue;
      }
      const kind = i % 4 < 2 ? "read" : i % 4 === 2 ? "command" : "replay";
      const pair = Math.floor(i / 4);
      const name = phase.name + "-" + pair;
      let promise;
      if (kind === "read") {
        promise = request(
          i % 2 ? "/api/v1/projects?limit=20&q=Catalog" : "/api/v1/creators?limit=20",
        );
      } else {
        if (!commands.has(name))
          commands.set(name, {
            key: randomUUID(),
            body: {
              project: {
                title: fixture.prefix + name,
                description: "Mixed workload command",
                category: "Дизайн",
                budget_minor: 100005,
                currency: "RUB",
                deadline: new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10),
              },
            },
            accepted_ids: new Set(),
          });
        const command = commands.get(name);
        promise = request("/api/v1/projects", "POST", command.body, command.key).then((sample) => {
          if (sample.status === 201) command.accepted_ids.add(sample.id);
          return sample;
        });
      }
      const pending = promise
        .then((sample) => {
          const result = {
            phase: phase.name,
            kind,
            status: sample.status,
            code: sample.code,
            elapsed_ms: sample.elapsed_ms,
          };
          own.push(result);
          samples.push(result);
        })
        .finally(() => inFlight.delete(pending));
      inFlight.add(pending);
    }
    await Promise.all(inFlight);
    if (blocker)
      await new Promise((resolve) =>
        blocker.exitCode !== null ? resolve() : blocker.once("exit", resolve),
      );
    const values = own.map((sample) => sample.elapsed_ms).sort((a, b) => a - b);
    const p = (fraction) => values[Math.max(0, Math.ceil(values.length * fraction) - 1)] ?? null;
    const statuses = {};
    for (const sample of own) statuses[sample.status] = (statuses[sample.status] ?? 0) + 1;
    const summary = {
      ...phase,
      requests: own.length,
      dropped_arrivals: dropped,
      statuses,
      p50_ms: p(0.5),
      p95_ms: p(0.95),
      p99_ms: p(0.99),
      latency_by_class: Object.fromEntries(
        ["read", "command", "replay"].map((kind) => {
          const times = own
            .filter((s) => s.kind === kind)
            .map((s) => s.elapsed_ms)
            .sort((a, b) => a - b);
          return [
            kind,
            {
              count: times.length,
              p95_ms: times[Math.max(0, Math.ceil(times.length * 0.95) - 1)] ?? null,
            },
          ];
        }),
      ),
    };
    summaries.push(summary);
  }
} finally {
  clearInterval(monitor);
  if (sampling) await sampling;
}
const recoveryStarted = performance.now();
let ready = false;
while (performance.now() - recoveryStarted < config.recovery_seconds * 1000) {
  if (
    (await request("/ready")).status === 200 &&
    (await request("/api/v1/projects?limit=20")).status === 200
  ) {
    ready = true;
    break;
  }
  await sleep(1000);
}
assert.ok(ready);
const readinessRecoveryMs = performance.now() - recoveryStarted;
for (const command of commands.values()) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const sample = await request("/api/v1/projects", "POST", command.body, command.key);
    if (sample.status === 201) {
      command.accepted_ids.add(sample.id);
      break;
    }
    assert.ok([429, 503, 0].includes(sample.status), "Unexpected recovery rejection");
    await sleep(1000);
  }
  assert.equal(
    command.accepted_ids.size,
    1,
    "One accepted operation must yield exactly one project",
  );
}
const backlogStarted = performance.now();
let verified;
while (performance.now() - backlogStarted < config.backlog_seconds * 1000) {
  verified = probe("verify");
  if (verified.pending === 0 && verified.notifications === commands.size) break;
  await sleep(2000);
}
agent.destroy();
const report = {
  checked_at: new Date().toISOString(),
  environment: "Ephemeral Ubuntu, TLS production digests, runtime DB role",
  config,
  phases: summaries,
  telemetry,
  samples,
  commands: commands.size,
  verified,
  readiness_recovery_ms: readinessRecoveryMs,
  backlog_recovery_ms: performance.now() - backlogStarted,
  scope:
    "Open arrival schedule with explicit client drops, 10k synthetic catalog rows, real authenticated writes/replays and notification worker. Final contention is deliberate; no production capacity/SLO extrapolation.",
};
await writeFile(path.join(evidence, "mixed-load.json"), JSON.stringify(report, null, 2) + "\n");
const baseline = summaries[0];
assert.equal(baseline.dropped_arrivals, 0);
assert.ok(baseline.p95_ms < config.baseline_max_p95_ms);
assert.equal(
  Object.entries(baseline.statuses).filter(([status]) => !["200", "201"].includes(status)).length,
  0,
);
assert.ok(
  samples.some((sample) => sample.status === 429),
  "Controlled overload must prove actual admission rejection",
);
assert.ok(samples.every((sample) => [200, 201, 429, 503, 0].includes(sample.status)));
assert.equal(verified.projects, commands.size);
assert.equal(verified.events, commands.size);
assert.equal(verified.processed, commands.size);
assert.equal(verified.notifications, commands.size);
assert.equal(verified.duplicate_events, 0);
assert.equal(verified.duplicate_effects, 0);
console.log(
  JSON.stringify({
    phases: summaries,
    commands: commands.size,
    exactly_once_effects: verified.notifications,
  }),
);
