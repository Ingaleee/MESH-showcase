import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 120000,
  expect: { timeout: 20000 },
  fullyParallel: false,
  workers: 1,
  reporter: [
    ["list"],
    ["json", { outputFile: `${process.env.MESH_EVIDENCE_DIR ?? "docs/evidence"}/playwright.json` }],
  ],
  use: {
    baseURL: process.env.MESH_BASE_URL ?? "http://localhost:3200",
    channel:
      process.env.PLAYWRIGHT_CHANNEL ?? (process.platform === "win32" ? "msedge" : "chromium"),
    headless: true,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    actionTimeout: 15000,
  },
});
