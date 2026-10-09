import http from "node:http";
import { createHash, randomUUID } from "node:crypto";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";

// Loopback HTTP exercises the real Puma process; production assume_ssl models its proxy.
// This probe claims authorization and DB-role parity, not a new TLS transport test.
export async function verifyRecoveredRuntime({ dc, root, restored }) {
  let cookie = "",
    csrf = "";
  async function request(method, route, body, authenticated = true, key) {
    const bytes = body ? Buffer.from(JSON.stringify(body)) : null;
    return new Promise((resolve, reject) => {
      const req = http.request(
        {
          hostname: "localhost",
          port: 3251,
          path: route,
          method,
          headers: {
            Host: "localhost",
            Origin: "https://localhost",
            ...(authenticated && cookie ? { Cookie: cookie } : {}),
            ...(method !== "GET" ? { "X-CSRF-Token": csrf } : {}),
            ...(bytes
              ? { "Content-Type": "application/json", "Content-Length": bytes.length }
              : {}),
            ...(key ? { "Idempotency-Key": key } : {}),
          },
        },
        (res) => {
          const chunks = [];
          let size = 0;
          res.on("data", (chunk) => {
            size += chunk.length;
            if (size > 2100000) {
              req.destroy(Error("Recovery response exceeds artifact budget"));
              return;
            }
            chunks.push(chunk);
          });
          res.on("error", reject);
          res.on("end", () => {
            if (authenticated && res.headers["set-cookie"])
              cookie = res.headers["set-cookie"].map((value) => value.split(";")[0]).join("; ");
            const raw = Buffer.concat(chunks);
            let data = null;
            try {
              data = JSON.parse(raw);
            } catch {}
            resolve({ status: res.statusCode, raw, data });
          });
        },
      );
      req.setTimeout(15000, () => req.destroy(Error("Recovery HTTP deadline")));
      req.on("error", reject);
      if (bytes) req.write(bytes);
      req.end();
    });
  }
  const session = await request("GET", "/api/v1/session");
  assert.equal(session.status, 200);
  csrf = session.data.csrf_token;
  const login = await request("POST", "/api/v1/session", {
    session: { email: "dr-operator@probe.test", password: "RecoveryProbe2026!" },
  });
  assert.equal(login.status, 200);
  csrf = login.data.csrf_token;
  assert.ok(csrf);
  const artifactPath =
    "/api/v1/publishing/candidates/" + restored.private_candidate_id + "/artifact";
  const artifact = await request("GET", artifactPath);
  assert.equal(artifact.status, 200);
  assert.equal(
    createHash("sha256").update(artifact.raw).digest("hex"),
    restored.private_artifact_sha256,
  );
  const anonymous = await request("GET", artifactPath, null, false);
  assert.ok([401, 403].includes(anonymous.status), "Anonymous private artifact must be denied");
  const probe = (action) =>
    JSON.parse(
      dc(
        [
          "exec",
          "-T",
          "-e",
          "MESH_DR_RUNTIME_PROBE=true",
          "api",
          "bundle",
          "exec",
          "ruby",
          "script/recovery_runtime_probe.rb",
          action,
        ],
        true,
      )
        .split("\n")
        .at(-1),
    );
  assert.equal(probe("role").role, "mesh_runtime");
  dc(["up", "-d", "scanner", "worker", "dispatcher"]);
  const body = {
    project: {
      title: "Fresh VM recovery verification",
      description: "A real post-recovery command and notification.",
      category: "Дизайн",
      budget_minor: 100005,
      currency: "RUB",
      deadline: new Date(Date.now() + 21 * 86400000).toISOString().slice(0, 10),
    },
  };
  const key = randomUUID();
  const created = await request("POST", "/api/v1/projects", body, true, key);
  assert.equal(created.status, 201);
  const replay = await request("POST", "/api/v1/projects", body, true, key);
  assert.equal(replay.status, 201);
  assert.equal(created.data.id, replay.data.id);
  restored.runtime_project_id = created.data.id;
  await writeFile(
    path.join(root, "evidence/restored.json"),
    JSON.stringify(restored, null, 2) + "\n",
  );
  const began = Date.now();
  let result;
  while (Date.now() - began < 120000) {
    result = probe("check");
    if (result.processed === 1 && result.notifications === 1) break;
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  assert.equal(result.events, 1);
  assert.equal(result.processed, 1);
  assert.equal(result.notifications, 1);
  assert.equal(result.external_post_count, restored.external_post_count_after);
  assert.equal(result.pending_deployments, 0);
  Object.assign(restored, {
    runtime_private_http_artifact_verified: true,
    anonymous_private_download_denied: true,
    runtime_database_role: result.role,
    background_processing_resumed: true,
    post_restore_command_replayed_once: true,
    post_restore_notification_effects: result.notifications,
    external_post_count_after_workers: result.external_post_count,
    post_restore_notification_wait_ms: Date.now() - began,
    runtime_probe_transport:
      "Loopback HTTP to real Puma; production assume_ssl, not an additional TLS test",
  });
}
