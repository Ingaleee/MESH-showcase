import http from "node:http";
import { timingSafeEqual } from "node:crypto";
import { mkdir, appendFile, stat, rename } from "node:fs/promises";

const token = process.env.MESH_ALERT_TOKEN;
if (!token || token.length < 32) throw new Error("Set a receiver token.");
const directory = process.env.MESH_ALERT_DATA ?? "/data";
await mkdir(directory, { recursive: true });
const server = http.createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/health") {
    response.writeHead(200).end("ok"); return;
  }
  const supplied = Buffer.from(request.headers.authorization ?? "");
  const expected = Buffer.from(`Bearer ${token}`);
  if (request.method !== "POST" || request.url !== "/alerts" || supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
    response.writeHead(401).end(); return;
  }
  let size = 0;
  const chunks = [];
  try {
    for await (const chunk of request) {
      size += chunk.length;
      if (size > 65536) { response.writeHead(413).end(); return; }
      chunks.push(chunk);
    }
    const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!Array.isArray(body.alerts)) throw Object.assign(new Error("Missing alerts."), { badPayload: true });
    const receipt = {
      received_at: new Date().toISOString(),
      status: body.status,
      alerts: body.alerts.map((alert) => ({ name: alert.labels?.alertname, status: alert.status, severity: alert.labels?.severity, starts_at: alert.startsAt, ends_at: alert.endsAt })),
    };
    const line = JSON.stringify(receipt) + "\n";
    // Two bounded files preserve the latest delivered timeline across process restarts.
    const storedSize = await stat(directory + "/receipts.jsonl").then(info => info.size).catch(error => {
      if (error.code === "ENOENT") return 0; throw error;
    });
    if (storedSize + Buffer.byteLength(line) > 8 * 1024 * 1024)
      await rename(directory + "/receipts.jsonl", directory + "/receipts.previous.jsonl");
    await appendFile(directory + "/receipts.jsonl", line);
    response.writeHead(200).end("accepted");
  } catch (error) {
    const invalid = error instanceof SyntaxError || error.badPayload;
    if (!invalid) console.error("Receipt persistence failed:", error.code ?? error.name);
    response.writeHead(invalid ? 400 : 503).end(invalid ? "invalid payload" : "receipt storage unavailable");
  }
});
server.listen(Number(process.env.MESH_ALERT_PORT ?? 8080), "0.0.0.0", () => {
  console.log(JSON.stringify({ listening_port: server.address().port }));
});
