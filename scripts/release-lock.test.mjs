import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
test(
  "OS lock survives Node death while a Docker-equivalent child still owns fd 9",
  { skip: process.platform !== "linux" },
  async () => {
    const directory = await mkdtemp(path.join(tmpdir(), "mesh-lock-"));
    const lock = path.join(directory, "lock");
    const code =
      'require("node:child_process").spawn("sleep",["3"],{stdio:["ignore","ignore","ignore",...Array(6).fill("ignore"),9]}); console.log("ready"); setTimeout(()=>{},10000)';
    const owner = spawn(
      "bash",
      ["-c", 'exec 9>"$1"; flock -n 9; exec node -e "$2"', "mesh-lock-test", lock, code],
      { stdio: ["ignore", "pipe", "inherit"] },
    );
    try {
      await new Promise((resolve, reject) => {
        owner.stdout.once("data", resolve);
        owner.once("error", reject);
        owner.once("exit", () => reject(Error("owner died before barrier")));
      });
      const exited = new Promise((resolve) => owner.once("exit", resolve));
      owner.kill("SIGKILL");
      await exited;
      assert.notEqual(spawnSync("flock", ["-n", lock, "true"]).status, 0);
      await new Promise((resolve) => setTimeout(resolve, 3400));
      assert.equal(spawnSync("flock", ["-n", lock, "true"]).status, 0);
    } finally {
      owner.kill("SIGKILL");
      await rm(directory, { recursive: true });
    }
  },
);
