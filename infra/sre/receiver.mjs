import http from "node:http";
import { timingSafeEqual } from "node:crypto";
import { mkdir, appendFile, stat, rename } from "node:fs/promises";

const token = process.env.MESH_ALERT_TOKEN;
if (!token || token.length < 32) throw new Error("Set a receiver token.");
await mkdir("/data", { recursive: true });
http.createServer(async (request, response) => {
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
    if (!Array.isArray(body.alerts)) throw new Error("Missing alerts.");
    const receipt = {
      received_at: new Date().toISOString(),
      status: body.status,
      alerts: body.alerts.map((alert) => ({ name: alert.labels?.alertname, status: alert.status, severity: alert.labels?.severity, starts_at: alert.startsAt, ends_at: alert.endsAt })),
    };
    const line = JSON.stringify(receipt) + "\n";
    // Two bounded files preserve the latest delivered timeline across process restarts.
    const size = await stat("/data/receipts.jsonl").then(info => info.size).catch(error => {
      if (error.code === "ENOENT") return 0; throw error;
    });
    if (size + Buffer.byteLength(line) > 8 * 1024 * 1024)
      await rename("/data/receipts.jsonl", "/data/receipts.previous.jsonl");
    await appendFile("/data/receipts.jsonl", line);
    response.writeHead(200).end("accepted");
  } catch {
    response.writeHead(400).end("invalid payload");
  }
}).listen(8080, "0.0.0.0");
