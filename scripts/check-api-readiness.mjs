import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { request as httpRequest } from "node:http";

const reachable = "http://127.0.0.1:3212";
const unavailable = "http://127.0.0.1:3213";
const headers = { Host: "mesh.example.test" };
const request = (base, path) =>
  new Promise((resolve, reject) => {
    const outgoing = httpRequest(base + path, { headers }, (incoming) => {
      const chunks = [];
      incoming.on("data", (chunk) => chunks.push(chunk));
      incoming.on("error", reject);
      incoming.on("end", () =>
        resolve(
          new Response(Buffer.concat(chunks), {
            status: incoming.statusCode,
            headers: incoming.headers,
          }),
        ),
      );
    });
    const deadline = setTimeout(() => outgoing.destroy(new Error("HTTP probe timed out")), 6000);
    outgoing.on("error", reject);
    outgoing.on("close", () => clearTimeout(deadline));
    outgoing.end();
  });

async function waitForBoot(base) {
  let lastError;
  for (let attempt = 0; attempt < 30; attempt++) {
    try {
      const response = await request(base, "/up");
      if (response.status === 200) return;
      lastError = new Error(`Liveness returned ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw lastError;
}

await waitForBoot(reachable);
await waitForBoot(unavailable);
const ready = await request(reachable, "/ready");
assert.equal(ready.status, 200);
assert.equal(ready.headers.get("cache-control"), "no-store");
assert.deepEqual(await ready.json(), { status: "ready" });
const feed = await request(reachable, "/api/v1/projects?limit=1");
assert.equal(feed.status, 200);
assert.ok((await feed.json()).data.length > 0);
const started = performance.now();
const outage = await request(unavailable, "/ready");
const elapsed = Math.round(performance.now() - started);
assert.equal(outage.status, 503);
assert.deepEqual(await outage.json(), { status: "unavailable" });
assert.equal((await request(unavailable, "/up")).status, 200);
assert.ok(elapsed < 6000);
const result = {
  checkedAt: new Date().toISOString(),
  environment: "production",
  databaseReady: 200,
  publicFeed: 200,
  unavailableDatabaseReady: 503,
  unavailableDatabaseLiveness: 200,
  outageCheckMs: elapsed,
  cacheControl: "no-store",
  databaseWrites: false,
  scope:
    "Two isolated production API containers. The outage container connects to a closed PostgreSQL port; the shared local database is not stopped. Authentication and background writes are verified separately by RSpec and E2E.",
};
await writeFile(
  "docs/evidence/backend-hardening/production-readiness.json",
  JSON.stringify(result, null, 2) + "\n",
);
console.log(JSON.stringify(result));
