import http, { type IncomingMessage, type ServerResponse } from "node:http";
import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdirSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import path from "node:path";

const token = process.env.MESH_PARTNER_TOKEN_SHOWCASE ?? "";
if (token.length < 32) throw new Error("Configure a generated partner token.");
const port = Number(process.env.PORT ?? 3216);
const dataDir = process.env.MESH_PARTNER_STORAGE ?? "/data";
mkdirSync(dataDir, { recursive: true });
const database = new DatabaseSync(path.join(dataDir, "partner.sqlite"));
database.exec(`
  PRAGMA journal_mode=WAL;
  CREATE TABLE IF NOT EXISTS deployments (
    operation_id TEXT PRIMARY KEY, partner_id TEXT NOT NULL,
    artifact_sha256 TEXT NOT NULL, payload TEXT NOT NULL, artifact BLOB NOT NULL,
    sequence INTEGER UNIQUE NOT NULL, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS callbacks (
    event_id TEXT PRIMARY KEY, operation_id TEXT NOT NULL UNIQUE,
    payload TEXT NOT NULL, partner_id TEXT NOT NULL, due_at INTEGER NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0, delivered_at TEXT, last_status INTEGER
  );
  CREATE TABLE IF NOT EXISTS requests (route TEXT PRIMARY KEY, count INTEGER NOT NULL);
`);
const callbackOrigin = new URL(process.env.MESH_PARTNER_CALLBACK_ORIGIN ?? "http://api:3000");
if (
  callbackOrigin.username ||
  callbackOrigin.password ||
  callbackOrigin.pathname !== "/" ||
  !["http:", "https:"].includes(callbackOrigin.protocol)
)
  throw new Error("Invalid administrator-configured callback origin.");

type Observation = {
  operation_id: string;
  candidate_id: string;
  artifact_sha256: string;
  contract_version: string;
  state: "active";
  deployment_id: string;
  sequence: number;
};
type Row = {
  operation_id: string;
  partner_id: string;
  artifact_sha256: string;
  payload: string;
  artifact: Uint8Array;
  sequence: number;
  created_at: string;
};
type Callback = { event_id: string; partner_id: string; payload: string; attempts: number };
const uuid = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(value);
const auth = (request: IncomingMessage) => {
  const supplied = Buffer.from(request.headers.authorization ?? "");
  const expected = Buffer.from("Bearer " + token);
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
};
function json(response: ServerResponse, status: number, body: unknown) {
  response.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" });
  response.end(JSON.stringify(body));
}
async function body(request: IncomingMessage): Promise<Record<string, unknown>> {
  const parts: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const data = Buffer.from(chunk);
    size += data.length;
    if (size > 3_000_000) throw new Error("REQUEST_LIMIT");
    parts.push(data);
  }
  const parsed: unknown = JSON.parse(Buffer.concat(parts).toString("utf8"));
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    throw new Error("SCHEMA_INVALID");
  return parsed as Record<string, unknown>;
}
function tally(route: string) {
  database
    .prepare("INSERT INTO requests VALUES (?,1) ON CONFLICT(route) DO UPDATE SET count=count+1")
    .run(route);
}
async function sendCallback(row: Callback) {
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signature = createHmac("sha256", token)
    .update(timestamp + "." + row.event_id + "." + row.payload)
    .digest("hex");
  let status = 0;
  try {
    const response = await fetch(
      new URL("/api/v1/publishing/callbacks/" + row.partner_id, callbackOrigin),
      {
        method: "POST",
        redirect: "error",
        signal: AbortSignal.timeout(3_000),
        headers: {
          "content-type": "application/json",
          "x-event-id": row.event_id,
          "x-callback-timestamp": timestamp,
          "x-callback-signature": signature,
        },
        body: row.payload,
      },
    );
    status = response.status;
    await response.body?.cancel();
  } catch {
    /* Durable retry records the outcome, never the secret or response body. */
  }
  database
    .prepare(
      "UPDATE callbacks SET attempts=attempts+1, last_status=?, due_at=?, delivered_at=CASE WHEN ?=200 THEN ? ELSE delivered_at END WHERE event_id=?",
    )
    .run(status, Date.now() + 5_000, status, new Date().toISOString(), row.event_id);
}
let pumping = false;
const timer = setInterval(async () => {
  if (pumping) return;
  pumping = true;
  try {
    const rows = database
      .prepare(
        "SELECT * FROM callbacks WHERE delivered_at IS NULL AND due_at<=? AND attempts<5 LIMIT 5",
      )
      .all(Date.now()) as unknown as Callback[];
    for (const row of rows) await sendCallback(row);
  } finally {
    pumping = false;
  }
}, 500);

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? "/", "http://partner");
    if (url.pathname === "/health" && request.method === "GET")
      return json(response, 200, { ready: true });
    if (url.pathname === "/launch" && request.method === "GET") {
      const row = database
        .prepare("SELECT * FROM deployments ORDER BY sequence DESC LIMIT 1")
        .get() as unknown as Row | undefined;
      response.writeHead(200, {
        "content-type": "text/html; charset=utf-8",
        "content-security-policy":
          "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",
        "x-content-type-options": "nosniff",
        "cache-control": "no-store",
      });
      response.end(`<!doctype html><html lang="en"><meta name="viewport" content="width=device-width"><title>MESH Partner Sandbox</title>
        <style>body{background:#11101a;color:#f7f5ff;font:18px system-ui;margin:8vw}small{color:#b3a2ec}h1{font-size:clamp(38px,7vw,82px);max-width:800px}code{overflow-wrap:anywhere}main{max-width:850px;padding:40px;border:1px solid #60507c;border-radius:24px}b{color:#b191ff}</style>
        <small>INDEPENDENT TYPESCRIPT PARTNER · STATIC ARTIFACT SANDBOX</small>
        <h1>Validated bytes.<br><b>Traceable releases.</b></h1><main>
        <p>${row ? "Published artifact is retained under its exact digest." : "Waiting for a validated release."}</p>
        <p>Sequence: <b>${row?.sequence ?? 0}</b></p><code>${row?.artifact_sha256 ?? "—"}</code>
        <p>Uploaded code is stored as an artifact; this trusted preview does not execute it.</p></main></html>`);
      return;
    }
    if (!auth(request)) return json(response, 401, { code: "AUTH_REQUIRED" });
    if (url.pathname === "/contract" && request.method === "GET") {
      tally("contract");
      return json(response, 200, {
        contract_version: "1",
        capabilities: ["publish", "lookup", "signed_callbacks"],
      });
    }
    if (url.pathname === "/state" && request.method === "GET") {
      return json(response, 200, {
        deployments: database.prepare("SELECT COUNT(*) AS count FROM deployments").get(),
        active:
          database
            .prepare(
              "SELECT operation_id,artifact_sha256,sequence FROM deployments ORDER BY sequence DESC LIMIT 1",
            )
            .get() ?? null,
        requests: database.prepare("SELECT route,count FROM requests ORDER BY route").all(),
        callbacks: database
          .prepare(
            "SELECT event_id,operation_id,attempts,last_status,delivered_at FROM callbacks ORDER BY due_at DESC LIMIT 20",
          )
          .all(),
      });
    }
    const operation = /^\/deployments\/([0-9a-f-]{36})$/.exec(url.pathname);
    if (operation && request.method === "GET") {
      tally("lookup");
      const row = database
        .prepare("SELECT * FROM deployments WHERE operation_id=?")
        .get(operation[1]) as unknown as Row | undefined;
      return json(response, row ? 200 : 404, row ? JSON.parse(row.payload) : { code: "NOT_FOUND" });
    }
    const artifact = /^\/artifacts\/([0-9a-f-]{36})$/.exec(url.pathname);
    if (artifact && request.method === "GET") {
      const row = database
        .prepare("SELECT * FROM deployments WHERE operation_id=?")
        .get(artifact[1]) as unknown as Row | undefined;
      if (!row) return json(response, 404, { code: "NOT_FOUND" });
      response.writeHead(200, {
        "content-type": "application/zip",
        "cache-control": "private, no-store",
        "content-disposition": 'attachment; filename="validated-artifact.zip"',
      });
      response.end(Buffer.from(row.artifact));
      return;
    }
    if (url.pathname === "/deployments" && request.method === "POST") {
      tally("publish");
      const input = await body(request);
      if (
        !uuid(input.operation_id) ||
        !uuid(input.partner_id) ||
        !uuid(input.candidate_id) ||
        input.contract_version !== "1" ||
        typeof input.artifact_sha256 !== "string" ||
        !/^[a-f0-9]{64}$/.test(input.artifact_sha256) ||
        typeof input.artifact_base64 !== "string" ||
        !["publish", "rollback"].includes(String(input.kind)) ||
        !["normal", "timeout_after_success"].includes(String(input.scenario))
      )
        return json(response, 422, { code: "SCHEMA_INVALID" });
      if (input.scenario !== "normal" && process.env.MESH_PUBLISHING_FAILPOINTS !== "true")
        return json(response, 422, { code: "FAILPOINTS_DISABLED" });
      const bytes = Buffer.from(input.artifact_base64, "base64");
      if (
        !bytes.length ||
        bytes.length > 2_000_000 ||
        createHash("sha256").update(bytes).digest("hex") !== input.artifact_sha256
      )
        return json(response, 422, { code: "DIGEST_MISMATCH" });
      const prior = database
        .prepare("SELECT * FROM deployments WHERE operation_id=?")
        .get(input.operation_id) as unknown as Row | undefined;
      if (prior) {
        const observation = JSON.parse(prior.payload) as Observation;
        if (
          prior.partner_id !== input.partner_id ||
          observation.candidate_id !== input.candidate_id ||
          prior.artifact_sha256 !== input.artifact_sha256
        )
          return json(response, 409, { code: "IDEMPOTENCY_CONFLICT" });
        return json(response, 200, observation);
      }
      database.exec("BEGIN IMMEDIATE");
      let observation: Observation;
      try {
        const next = database
          .prepare("SELECT COALESCE(MAX(sequence),0)+1 AS value FROM deployments")
          .get() as { value: number };
        observation = {
          operation_id: input.operation_id,
          candidate_id: input.candidate_id,
          artifact_sha256: input.artifact_sha256,
          contract_version: "1",
          state: "active",
          deployment_id: "partner-" + input.operation_id,
          sequence: next.value,
        };
        const payload = JSON.stringify(observation);
        database
          .prepare("INSERT INTO deployments VALUES (?,?,?,?,?,?,?)")
          .run(
            input.operation_id,
            input.partner_id,
            input.artifact_sha256,
            payload,
            bytes,
            next.value,
            new Date().toISOString(),
          );
        database
          .prepare(
            "INSERT INTO callbacks (event_id,operation_id,payload,partner_id,due_at) VALUES (?,?,?,?,?)",
          )
          .run(
            randomUUID(),
            input.operation_id,
            payload,
            input.partner_id,
            Date.now() + (input.scenario === "normal" ? 1_000 : 60_000),
          );
        database.exec("COMMIT");
      } catch (error) {
        database.exec("ROLLBACK");
        throw error;
      }
      if (input.scenario === "timeout_after_success") {
        // Commit happened; the client times out before this response. Lookup is required.
        await new Promise((resolve) => setTimeout(resolve, 6_000));
      }
      return json(response, 200, observation);
    }
    return json(response, 404, { code: "NOT_FOUND" });
  } catch {
    if (!response.headersSent) json(response, 400, { code: "REQUEST_INVALID" });
    else response.destroy();
  }
});
server.maxConnections = 24;
server.headersTimeout = 5_000;
server.requestTimeout = 8_000;
server.keepAliveTimeout = 1_000;
server.listen(port, "0.0.0.0", () => console.log(JSON.stringify({ event: "partner.ready", port })));
function shutdown() {
  clearInterval(timer);
  server.close(() => {
    const finish = setInterval(() => {
      if (pumping) return;
      clearInterval(finish);
      database.close();
      process.exit(0);
    }, 50);
  });
  setTimeout(() => process.exit(1), 8_000).unref();
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
