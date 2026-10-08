import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
test("authenticated webhook writes a fresh receipt, and malformed requests cannot write", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "mesh-receiver-"));
  const token = randomBytes(32).toString("hex");
  const child = spawn(process.execPath, ["infra/sre/receiver.mjs"], {
    env: { ...process.env, MESH_ALERT_TOKEN: token, MESH_ALERT_DATA: root, MESH_ALERT_PORT: "0" },
    stdio: ["ignore", "pipe", "pipe"]
  });
  try {
    const port = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(Error("Receiver startup timed out")), 5000);
      child.once("error", reject);
      child.stdout.once("data", bytes => { clearTimeout(timeout); resolve(JSON.parse(bytes.toString()).listening_port); });
    });
    const send = (body, auth = token) => fetch("http://127.0.0.1:" + port + "/alerts",
      { method: "POST", headers: { Authorization: "Bearer " + auth, "Content-Type": "application/json" }, body });
    assert.equal((await send(JSON.stringify({ status: "firing", alerts: [{ labels: { alertname: "FreshReceipt" }, status: "firing" }] }))).status, 200);
    assert.equal((await send("{")).status, 400);
    assert.equal((await send("{}")).status, 400);
    assert.equal((await send("{}", "wrong")).status, 401);
    const receipts = (await readFile(path.join(root, "receipts.jsonl"), "utf8")).trim().split("\n").map(JSON.parse);
    assert.equal(receipts.length, 1);
    assert.equal(receipts[0].alerts[0].name, "FreshReceipt");
  } finally {
    const stopped = new Promise(resolve => child.once("exit", resolve));
    if (child.exitCode === null && child.signalCode === null) { child.kill(); await stopped; }
    await rm(root, { recursive: true });
  }
});
