import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { chromium } from "@playwright/test";

const url = process.env.MESH_PRODUCTION_WEB_URL || "http://localhost:3210";
const first = await fetch(url);
assert.equal(first.status, 200);
const policy = first.headers.get("content-security-policy");
assert.ok(policy?.includes("'strict-dynamic'"));
assert.ok(!policy.includes("'unsafe-eval'"));
const scriptPolicy = policy.split(";").find((rule) => rule.trim().startsWith("script-src "));
assert.ok(scriptPolicy && !scriptPolicy.includes("'unsafe-inline'"));
const nonce = policy.match(/'nonce-([^']+)'/)?.[1];
assert.ok(nonce);
const html = await first.text();
const scripts = [...html.matchAll(/<script\b[^>]*>/g)].map((match) => match[0]);
assert.ok(scripts.length > 0);
assert.ok(scripts.every((script) => script.includes(`nonce="${nonce}"`)));
assert.equal(first.headers.get("x-content-type-options"), "nosniff");
const second = await fetch(url);
assert.notEqual(second.headers.get("content-security-policy"), policy);

const browser = await chromium.launch({
  channel: process.platform === "win32" ? "msedge" : "chromium",
});
const page = await browser.newPage();
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
await page.addInitScript(() => {
  window.meshCspViolations = [];
  document.addEventListener("securitypolicyviolation", (event) => {
    window.meshCspViolations.push({
      directive: event.effectiveDirective,
      blocked: event.blockedURI,
    });
  });
});
try {
  await page.goto(url);
  await page.getByRole("heading", { name: /Найдите людей/ }).waitFor();
  await page.keyboard.press("Control+k");
  assert.equal(
    await page
      .getByLabel("Поиск проектов", { exact: true })
      .evaluate((element) => element === document.activeElement),
    true,
  );
  const violations = await page.evaluate(() => window.meshCspViolations);
  assert.deepEqual(violations, []);
  assert.deepEqual(errors, []);
  const result = {
    timestamp: new Date().toISOString(),
    production: true,
    distinct_nonce_per_response: true,
    scripts_with_matching_nonce: scripts.length,
    unsafe_eval: false,
    browser_hydration_and_keyboard_verified: true,
    csp_violations: violations,
    javascript_errors: errors,
    scope: "Standalone production web image; API integration is covered separately by E2E.",
  };
  await writeFile("docs/evidence/production-csp.json", JSON.stringify(result, null, 2) + "\n");
  console.log(JSON.stringify(result, null, 2));
} finally {
  await browser.close();
}
