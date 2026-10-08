import { test, expect, type Page } from "@playwright/test";
import { reserveLogin } from "./support/login-budget";
import { mkdir } from "node:fs/promises";
import Ajv from "ajv/dist/2020";
import addFormats from "ajv-formats";
import contract from "../../contracts/openapi.json";

const evidenceDirectory = process.env.MESH_EVIDENCE_DIR ?? ".cache/browser-evidence";
test.beforeAll(async () => {
  await mkdir(evidenceDirectory, { recursive: true });
});

const ajv = new Ajv({ strict: false, allErrors: true });
addFormats(ajv);
ajv.addSchema({ $id: "mesh", components: contract.components });
function validate(name: string, value: unknown) {
  const check = ajv.compile({ $ref: `mesh#/components/schemas/${name}` });
  expect(check(value), JSON.stringify(check.errors)).toBe(true);
}

async function login(page: Page, email: string) {
  await reserveLogin();
  await expect(page.getByRole("button", { name: "Войти", exact: true })).toBeEnabled({
    timeout: 45000,
  });
  await page.getByRole("button", { name: "Войти", exact: true }).click();
  await page.getByLabel("Email", { exact: true }).fill(email);
  await page.getByRole("dialog").getByRole("button", { name: "Войти", exact: true }).click();
  await expect(page.getByRole("dialog")).not.toBeVisible();
  await expect(page.getByRole("button", { name: "Выйти", exact: true })).toBeVisible();
}

test("client and creator complete a real agreement and recover a lost provider response", async ({
  browser,
}) => {
  const clientContext = await browser.newContext();
  const creatorContext = await browser.newContext();
  const client = await clientContext.newPage();
  const creator = await creatorContext.newPage();
  await client.goto("/");
  await expect(client.getByRole("heading", { name: /Найдите людей/ })).toBeVisible();
  await login(client, "client@mesh.local");
  await client.getByRole("button", { name: "Создать проект", exact: true }).click();
  const title = `Проверенный проект ${Date.now()}`;
  await client.getByLabel("Название проекта", { exact: true }).fill(title);
  await client
    .getByLabel("Что нужно сделать", { exact: true })
    .fill("Подготовить понятный текст и передать окончательную версию.");
  await client.getByLabel("Бюджет, ₽", { exact: true }).fill("1000.05");
  const deadline = new Date();
  deadline.setDate(deadline.getDate() + 30);
  await client.getByLabel("Дедлайн", { exact: true }).fill(deadline.toISOString().slice(0, 10));
  await client.getByRole("button", { name: "Опубликовать проект", exact: true }).click();
  await expect(client.getByRole("heading", { name: title, exact: true })).toBeVisible();
  const projectUrl = client.url();
  const projectId = projectUrl.split("/").pop();
  const detail = await client.request.get(`/api/v1/projects/${projectId}`);
  validate("ProjectDetail", await detail.json());
  await client.getByRole("button", { name: "Редактировать бриф", exact: true }).click();
  const revisedBrief = "Подготовить понятный текст. Уточнены критерии приёмки и источники фактов.";
  await client.getByRole("textbox", { name: "Что нужно сделать", exact: true }).fill(revisedBrief);
  await client.getByRole("button", { name: "Сохранить новую версию", exact: true }).click();
  await expect(
    client.locator(".project-brief").getByText(revisedBrief, { exact: true }),
  ).toBeVisible();
  const revision = await client.request.get(`/api/v1/projects/${projectId}`);
  expect((await revision.json()).project.brief_version).toBe(2);
  await creator.goto(projectUrl);
  await login(creator, "creator@mesh.local");
  await creator.getByRole("button", { name: "Предложить цену и срок", exact: true }).click();
  await creator.getByLabel("Ваша цена, ₽", { exact: true }).fill("1000.05");
  await creator
    .getByLabel("Ваш подход", { exact: true })
    .fill("Сначала проверю факты, затем подготовлю текст и поясню решения.");
  await creator.getByRole("checkbox").check();
  await creator.getByRole("button", { name: "Отправить предложение", exact: true }).click();
  await expect(creator.getByText("Ваше предложение отправлено", { exact: true })).toBeVisible();
  await client.reload();
  await client.getByRole("link", { name: /Предложения/ }).click();
  await client.getByRole("button", { name: /Посмотреть предложение Саша Волкова/ }).click();
  await client.getByRole("button", { name: "Выбрать автора", exact: true }).click();
  await client
    .getByRole("dialog")
    .getByRole("button", { name: "Начать работу", exact: true })
    .click();
  await client.getByRole("link", { name: "Перейти к работе", exact: true }).click();
  await expect(client).toHaveURL(/workspace\?engagement=/);
  const engagementId = new URL(client.url()).searchParams.get("engagement");
  await creator.goto(client.url());
  await creator.getByRole("button", { name: "Передать новую версию", exact: true }).click();
  await creator.getByLabel("Название версии", { exact: true }).fill("Итоговый текст v1");
  await creator
    .getByLabel("Комментарий заказчику", { exact: true })
    .fill("Итоговый текст. Все факты проверены. Версия для приёмки.");
  await creator.getByRole("button", { name: "Передать заказчику", exact: true }).click();
  await expect(
    creator.getByText("Итоговый текст. Все факты проверены. Версия для приёмки.", { exact: true }),
  ).toBeVisible();
  await client.reload();
  await client.getByRole("button", { name: "Принять эту версию", exact: true }).click();
  await client.getByRole("button", { name: "Подтвердить приёмку", exact: true }).click();
  await expect(client.locator(".workroom-success")).toHaveText("Результат принят заказчиком");
  if (process.env.MESH_DEMO_MARKETPLACE_ONLY !== "true") {
    await client.getByRole("button", { name: "Расчёты", exact: true }).click();
    await client
      .getByRole("combobox", { name: "Сценарий симулятора", exact: true })
      .selectOption("timeout_after_success");
    await client.getByRole("button", { name: "Зарезервировать сумму", exact: true }).click();
    await expect(client.getByText("Подтверждено", { exact: true })).toBeVisible({ timeout: 45000 });
    await client.getByRole("button", { name: "Выплатить автору", exact: true }).click();
    await expect(client.getByText("Подтверждено", { exact: true })).toHaveCount(2, {
      timeout: 45000,
    });
    const financeResponse = await client.request.get(`/api/v1/engagements/${engagementId}/finance`);
    const finance = await financeResponse.json();
    validate("Finance", finance);
    expect(finance.operations).toHaveLength(2);
    expect(finance.ledger).toHaveLength(2);
    for (const journal of finance.ledger) {
      expect(
        journal.entries.reduce(
          (sum: number, entry: { direction: string; amount_minor: number }) =>
            sum + (entry.direction === "debit" ? entry.amount_minor : -entry.amount_minor),
          0,
        ),
      ).toBe(0);
    }
  }
  const agreement = await client.request.get(`/api/v1/engagements/${engagementId}`);
  validate("Engagement", await agreement.json());
  const noCsrf = await client.request.post(`/api/v1/engagements/${engagementId}/hold`, {
    data: { reason: "Missing CSRF" },
    headers: { "Idempotency-Key": crypto.randomUUID() },
  });
  expect(noCsrf.status()).toBe(403);
  const unauthorized = await creator.request.get("/api/v1/operations");
  expect(unauthorized.status()).toBe(403);
  await client.screenshot({ path: `${evidenceDirectory}/workspace-desktop.png`, fullPage: true });
  await clientContext.close();
  await creatorContext.close();
});

test("public directory, keyboard navigation and mobile layout work", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator(".project-card").first()).toBeVisible();
  await page.screenshot({ path: `${evidenceDirectory}/marketplace-desktop.png`, fullPage: true });
  await page.getByRole("button", { name: "Тексты", exact: true }).click();
  await expect(page.locator(".category-label").first()).toHaveText("Тексты");
  await page.getByRole("link", { name: "Авторы", exact: true }).click();
  await expect(page.getByRole("heading", { name: /Найдите своего автора/ })).toBeVisible();
  await page.getByLabel("Поиск авторов", { exact: true }).fill("UX-тексты");
  await expect(page.locator(".directory-card")).toHaveCount(1);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await expect(page.locator(".project-card").first()).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true,
  );
  await page.screenshot({ path: `${evidenceDirectory}/marketplace-mobile.png`, fullPage: true });
  const session = await page.request.get("/api/v1/session");
  validate("Session", await session.json());
});
