import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import { readFile, mkdir } from "node:fs/promises";
import { reserveLogin } from "./support/login-budget";

test("operator uploads, validates and publishes real private artifacts on responsive screens", async ({
  page,
}) => {
  test.setTimeout(180000);
  await page.goto("/publishing");
  await expect(page.getByText("Рабочее место оператора", { exact: true })).toBeVisible();
  await reserveLogin();
  const session = await (await page.request.get("/api/v1/session")).json();
  const login = await page.request.post("/api/v1/session", {
    data: { session: { email: "ops@mesh.local", password: "MeshDemo2026!" } },
    headers: { "X-CSRF-Token": session.csrf_token },
  });
  expect(login.status()).toBe(200);
  await page.reload();
  await page.emulateMedia({ reducedMotion: "reduce" });
  await expect(page.getByRole("heading", { name: "Кандидаты на выпуск" })).toBeVisible();
  const suffix = crypto.randomUUID().slice(0, 8);
  async function upload(name: string) {
    const manifest = JSON.parse(
      await readFile(".cache/publishing-fixtures/" + name + ".json", "utf8"),
    );
    manifest.title = "Browser Studio " + name + " " + suffix;
    await page
      .getByLabel("ZIP-артефакт", { exact: true })
      .setInputFiles(".cache/publishing-fixtures/" + name + ".zip");
    await page.getByLabel("Manifest JSON", { exact: true }).setInputFiles({
      name: "manifest.json",
      mimeType: "application/json",
      buffer: Buffer.from(JSON.stringify(manifest)),
    });
    await page.getByRole("button", { name: "Отправить на проверку" }).click();
    await expect(page.locator(".pub-detail h2")).toHaveText(manifest.title);
    return manifest.title as string;
  }
  await upload("bad");
  await expect(page.locator(".pub-report-meta .pub-state")).toHaveText("Отклонён", {
    timeout: 65000,
  });
  await expect(page.locator(".pub-checks")).toContainText("FILE_DIGEST");
  await expect(page.getByRole("button", { name: "Выпустить эту версию" })).toBeDisabled();
  await upload("v1");
  await expect(page.locator(".pub-report-meta .pub-state")).toHaveText("Проверка пройдена", {
    timeout: 65000,
  });
  await page.getByRole("button", { name: "Выпустить эту версию" }).click();
  await expect(page.locator(".pub-release .pub-state").first()).toHaveText("Подтверждён", {
    timeout: 65000,
  });
  await page.getByRole("button", { name: "Диагностика", exact: true }).first().click();
  await expect(page.locator(".pub-diagnostic")).toContainText("Входы проверки актуальны");
  await expect(page.locator(".pub-diagnostic")).toContainText("Да");
  const directory = (process.env.MESH_EVIDENCE_DIR ?? "docs/evidence") + "/publishing-ui";
  await mkdir(directory, { recursive: true });
  for (const width of [1440, 1024, 390]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(
      true,
    );
    const result = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(
      result.violations.map((row) => ({ id: row.id, nodes: row.nodes.map((node) => node.target) })),
    ).toEqual([]);
    await page.screenshot({ path: directory + "/" + width + ".png", fullPage: true });
  }
});

test("the provisioned dashboard opens with a healthy real Prometheus target", async ({ page }) => {
  test.skip(
    !!process.env.CI && process.env.MESH_TELEMETRY_ENABLED !== "true",
    "Local telemetry is a separate opt-in runtime, not a mocked CI datasource.",
  );
  const targets = await (await page.request.get("http://localhost:32091/api/v1/targets")).json();
  expect(targets.data.activeTargets[0].health).toBe("up");
  const queries = [
    "sum(mesh_http_request_seconds_count)",
    "mesh_notification_delivery_seconds_count",
    "mesh_validation_completion_seconds_count",
  ];
  for (const query of queries) {
    const data = await (
      await page.request.get(
        "http://localhost:32091/api/v1/query?query=" + encodeURIComponent(query),
      )
    ).json();
    expect(data.status).toBe("success");
    expect(Number(data.data.result[0].value[1])).toBeGreaterThan(0);
  }
  await expect
    .poll(
      async () => {
        try {
          return (
            await page.request.get("http://localhost:32092/api/health", { timeout: 3000 })
          ).ok();
        } catch {
          return false;
        }
      },
      { timeout: 45000 },
    )
    .toBe(true);
  await page.goto("http://localhost:32092/d/mesh-reliability");
  await expect(page.getByText("HTTP p95 · по маршрутам", { exact: true })).toBeVisible();
  await expect(page.getByText("Доставка уведомлений p95", { exact: true })).toBeVisible();
  const directory = (process.env.MESH_EVIDENCE_DIR ?? "docs/evidence") + "/publishing-ui";
  await mkdir(directory, { recursive: true });
  await page.setViewportSize({ width: 1600, height: 1200 });
  await expect(page.getByText("Loading plugin panel...", { exact: true })).toHaveCount(0, {
    timeout: 45000,
  });
  await expect(page.locator("canvas").first()).toBeVisible({ timeout: 45000 });
  await page.screenshot({ path: directory + "/dashboard.png", fullPage: true });
});
