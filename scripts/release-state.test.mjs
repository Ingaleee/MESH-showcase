import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { atomicJSON, recoverRelease } from "./release-state.mjs";

for (const phase of ["applying", "verified", "rolling_back"]) {
  test("recover interrupted " + phase + " to the verified baseline", async () => {
    const state = await mkdtemp(path.join(tmpdir(), "mesh-release-"));
    try {
      const baseline = { revision: "A" },
        target = { revision: "B" };
      await atomicJSON(path.join(state, "journal.json"), { phase, baseline, target });
      // Covers a crash after current.json was renamed but before commit was recorded.
      await atomicJSON(path.join(state, "current.json"), target);
      const calls = [];
      const recovery = await recoverRelease(
        state,
        async (release, migrate) => {
          calls.push({ release, migrate });
          return { healthy: true };
        },
        (value) => value,
      );
      assert.deepEqual(calls, [{ release: baseline, migrate: false }]);
      assert.equal(JSON.parse(await readFile(path.join(state, "current.json"))).revision, "A");
      assert.equal(recovery.phase, "recovered");
      assert.equal(
        await recoverRelease(
          state,
          () => {
            throw Error("duplicate recovery");
          },
          (v) => v,
        ),
        null,
      );
    } finally {
      await rm(state, { recursive: true });
    }
  });
}
test("failed recovery preserves journal and current for another safe attempt", async () => {
  const state = await mkdtemp(path.join(tmpdir(), "mesh-release-"));
  try {
    await atomicJSON(path.join(state, "journal.json"), {
      phase: "applying",
      baseline: { revision: "A" },
    });
    await assert.rejects(
      recoverRelease(
        state,
        () => {
          throw Error("host unavailable");
        },
        (v) => v,
      ),
      /host unavailable/,
    );
    assert.equal(JSON.parse(await readFile(path.join(state, "journal.json"))).phase, "applying");
  } finally {
    await rm(state, { recursive: true });
  }
});
