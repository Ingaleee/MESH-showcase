import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { atomicJSON, recoverRelease } from "./release-state.mjs";

test("unknown journal phase cannot execute infrastructure or advance current", async () => {
  const state = await mkdtemp(path.join(tmpdir(), "mesh-release-"));
  try {
    await atomicJSON(path.join(state, "journal.json"), {
      phase: "future_version",
      target: { revision: "B" },
    });
    await atomicJSON(path.join(state, "current.json"), { revision: "A" });
    await assert.rejects(
      recoverRelease(
        state,
        () => {
          throw Error("must not execute");
        },
        (v) => v,
      ),
      /Unknown release journal phase/,
    );
    assert.equal(JSON.parse(await readFile(path.join(state, "current.json"))).revision, "A");
  } finally {
    await rm(state, { recursive: true });
  }
});

test("rejected bootstrap permits a corrected release instead of replaying the bad intent forever", async () => {
  const state = await mkdtemp(path.join(tmpdir(), "mesh-release-"));
  try {
    await atomicJSON(path.join(state, "journal.json"), {
      phase: "rejected",
      baseline: null,
      target: { revision: "bad" },
    });
    assert.equal(
      await recoverRelease(
        state,
        () => {
          throw Error("must not retry rejected intent");
        },
        (v) => v,
      ),
      null,
    );
  } finally {
    await rm(state, { recursive: true });
  }
});

test("interrupted initial bootstrap reapplies its exact target including migrations", async () => {
  const state = await mkdtemp(path.join(tmpdir(), "mesh-release-"));
  try {
    await atomicJSON(path.join(state, "journal.json"), {
      phase: "applying",
      baseline: null,
      target: { revision: "B" },
    });
    const calls = [];
    await recoverRelease(
      state,
      async (target, migrate) => {
        calls.push({ target, migrate });
        return { healthy: true };
      },
      (v) => v,
    );
    assert.deepEqual(calls, [{ target: { revision: "B" }, migrate: true }]);
    assert.equal(JSON.parse(await readFile(path.join(state, "current.json"))).revision, "B");
  } finally {
    await rm(state, { recursive: true });
  }
});
