import { test, expect, type APIRequestContext, type Page } from "@playwright/test";
import { reserveLogin } from "./support/login-budget";
import AxeBuilder from "@axe-core/playwright";
import { readFile } from "node:fs/promises";

async function login(api: APIRequestContext, email: string) {
  await reserveLogin();
  const session = await (await api.get("/api/v1/session")).json();
  const response = await api.post("/api/v1/session", {
    data: { session: { email, password: "MeshDemo2026!" } },
    headers: { "X-CSRF-Token": session.csrf_token },
  });
  expect(response.status()).toBe(200);
  return (await response.json()).csrf_token as string;
}
function command(csrf: string, data: unknown) {
  return { data, headers: { "X-CSRF-Token": csrf, "Idempotency-Key": crypto.randomUUID() } };
}
async function agreement(
  client: APIRequestContext,
  author: APIRequestContext,
  clientCsrf: string,
  authorCsrf: string,
) {
  const project = await client.post(
    "/api/v1/projects",
    command(clientCsrf, {
      project: {
        title: `NORA рабочее пространство ${Date.now()}`,
        description: "Разработать визуальную систему и передать макеты упаковки.",
        category: "Дизайн",
        budget_minor: 12000000,
        currency: "RUB",
        deadline: new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10),
        deliverables: ["Логотип", "Макеты упаковки"],
        expected_result: "Редактируемые исходники и гайд.",
      },
    }),
  );
  expect(project.status()).toBe(201);
  const id = (await project.json()).id;
  const offer = await author.post(
    `/api/v1/projects/${id}/propose`,
    command(authorCsrf, {
      proposal: {
        price_minor: 9500000,
        delivery_days: 18,
        message: "Подготовлю визуальную систему и объясню решения.",
        brief_version: 1,
      },
    }),
  );
  expect(offer.status()).toBe(201);
  const award = await client.post(
    `/api/v1/projects/${id}/award`,
    command(clientCsrf, { proposal_id: (await offer.json()).id, brief_version: 1 }),
  );
  expect(award.status()).toBe(201);
  return (await award.json()).id as string;
}
async function composer(page: Page, title: string, content: string, ready = true) {
  await page.getByRole("button", { name: "Передать новую версию", exact: true }).click();
  await page.getByLabel("Название версии", { exact: true }).fill(title);
  await page.getByLabel("Комментарий заказчику", { exact: true }).fill(content);
  await page.getByRole("checkbox", { name: /Считаю эту версию/ }).setChecked(ready);
  await expect(
    page.getByRole("button", { name: /Перетащите файлы или выберите их/ }),
  ).toBeEnabled();
}

test("workspace preserves uploaded versions, requests changes and accepts only the latest ready result", async ({
  browser,
}) => {
  const authorContext = await browser.newContext();
  const clientContext = await browser.newContext();
  try {
    const authorCsrf = await login(authorContext.request, "design@mesh.local");
    const clientCsrf = await login(clientContext.request, "client@mesh.local");
    const id = await agreement(
      clientContext.request,
      authorContext.request,
      clientCsrf,
      authorCsrf,
    );
    const author = await authorContext.newPage();
    const client = await clientContext.newPage();
    const url = `/workspace?engagement=${id}`;
    await author.goto(url);
    await author.getByRole("button", { name: "Начать работу", exact: true }).click();
    await expect(author.locator(".workroom-project-status")).toHaveText("В работе");
    await composer(author, "NORA — концепция", "Первая концепция для обсуждения.", false);
    const file = await readFile("apps/web/public/images/projects/brand-paper.png");
    await author
      .getByLabel("Файлы результата", { exact: true })
      .setInputFiles({ name: "concept.png", mimeType: "image/png", buffer: file });
    await expect(author.locator(".workroom-upload-list li")).toHaveCount(1);
    await author.getByRole("button", { name: "Передать заказчику", exact: true }).click();
    await expect(author.getByRole("dialog")).not.toBeVisible();
    await expect(author.getByRole("article", { name: "Версия 1", exact: true })).toContainText(
      "Для обсуждения",
    );
    const firstResponse = await author.request.get(`/api/v1/engagements/${id}`);
    const first = (await firstResponse.json()).submissions[0];
    await client.goto(url);
    await expect(
      client.getByRole("button", { name: "Принять эту версию", exact: true }),
    ).toHaveCount(0);
    const rejected = await client.request.post(
      `/api/v1/engagements/${id}/accept`,
      command(clientCsrf, { submission_id: first.id }),
    );
    expect((await rejected.json()).code).toBe("NOT_READY");
    await client.getByRole("button", { name: "Запросить изменения", exact: true }).click();
    await client
      .getByLabel("Что нужно изменить", { exact: true })
      .fill("Сделайте знак мягче и добавьте упаковку.");
    await client.getByRole("button", { name: "Отправить замечания", exact: true }).click();
    await expect(client.getByRole("dialog")).not.toBeVisible();
    await author.reload();
    await expect(author.getByRole("article", { name: "Версия 1", exact: true })).toContainText(
      "Требуются изменения",
    );
    await composer(author, "NORA — готовая система", "Обновил знак и подготовил упаковку.");
    await author.getByRole("button", { name: "Передать заказчику", exact: true }).click();
    await expect(author.getByRole("dialog")).not.toBeVisible();
    await expect(author.getByRole("article", { name: "Версия 1", exact: true })).toContainText(
      "Сделайте знак мягче",
    );
    await client.reload();
    const stale = await client.request.post(
      `/api/v1/engagements/${id}/accept`,
      command(clientCsrf, { submission_id: first.id }),
    );
    expect((await stale.json()).code).toBe("STALE_SUBMISSION");
    await client.getByRole("button", { name: "Принять эту версию", exact: true }).click();
    await client.getByRole("button", { name: "Подтвердить приёмку", exact: true }).click();
    await expect(client.locator(".workroom-success")).toHaveText("Результат принят заказчиком");
    await author.reload();
    await expect(
      author.getByRole("button", { name: "Передать новую версию", exact: true }),
    ).toHaveCount(0);
    await expect
      .poll(
        async () =>
          (
            await (
              await author.request.get(`/api/v1/engagements/${id}/work_files/${first.files[0].id}`)
            ).json()
          ).state,
        { timeout: 60000 },
      )
      .toBe("available");
    const archive = await client.request.get(
      `/api/v1/engagements/${id}/archive?submission_id=${first.id}`,
    );
    expect(archive.status()).toBe(200);
    expect(archive.headers()["content-type"]).toContain("application/zip");
    expect((await archive.body()).subarray(0, 2).toString()).toBe("PK");
    const final = await (await client.request.get(`/api/v1/engagements/${id}`)).json();
    expect(final.submissions[1].sha256).toBe(first.sha256);
    expect(final.submissions[1].manifest_sha256).toBe(first.manifest_sha256);
    expect(final.feedback[0].submission_id).toBe(first.id);
    expect(final.terms.price_minor).toBe(9500000);
    expect(final.terms.delivery_days).toBe(18);
  } finally {
    await authorContext.close();
    await clientContext.close();
  }
});

test("workspace draft survives reload and accessible panels fit five widths", async ({
  browser,
}) => {
  const authorContext = await browser.newContext({ reducedMotion: "reduce" });
  const clientContext = await browser.newContext();
  try {
    const authorCsrf = await login(authorContext.request, "design@mesh.local");
    const clientCsrf = await login(clientContext.request, "client@mesh.local");
    const id = await agreement(
      clientContext.request,
      authorContext.request,
      clientCsrf,
      authorCsrf,
    );
    const page = await authorContext.newPage();
    await page.goto(`/workspace?engagement=${id}`);
    await composer(page, "Сохранённая концепция", "Мои решения остаются в черновике.");
    await page.reload();
    await page.getByRole("button", { name: "Передать новую версию", exact: true }).click();
    await expect(page.getByLabel("Название версии", { exact: true })).toHaveValue(
      "Сохранённая концепция",
    );
    await expect(page.getByLabel("Комментарий заказчику", { exact: true })).toHaveValue(
      "Мои решения остаются в черновике.",
    );
    await page.keyboard.press("Escape");
    for (const width of [320, 390, 768, 1024, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
      if ([390, 1440].includes(width)) {
        expect(
          (await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze())
            .violations,
        ).toEqual([]);
        await page.getByRole("button", { name: "Передать новую версию", exact: true }).click();
        expect(
          (await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze())
            .violations,
        ).toEqual([]);
        await page.keyboard.press("Escape");
      }
    }
    await page
      .getByRole("button", { name: "Посмотреть зафиксированные условия", exact: false })
      .click();
    await expect(page.getByRole("dialog")).toContainText("18 дней");
    await expect(page.getByRole("dialog")).toContainText("Макеты упаковки");
    await page.keyboard.press("Escape");
    await page.getByRole("button", { name: "Комментарии", exact: true }).click();
    await page
      .locator(".workroom-comments")
      .getByRole("button", { name: "Написать", exact: true })
      .click();
    await page
      .getByLabel("Сообщение", { exact: true })
      .fill("Уточним цвет упаковки перед первой передачей.");
    await page.getByRole("button", { name: "Отправить комментарий", exact: true }).click();
    await expect(page.getByRole("dialog")).not.toBeVisible();
    await expect(page.locator(".workroom-comments")).toContainText("Весь проект · Комментарий");
  } finally {
    await authorContext.close();
    await clientContext.close();
  }
});
