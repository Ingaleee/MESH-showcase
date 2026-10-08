import { test, expect, type Page } from "@playwright/test";
import { reserveLogin } from "./support/login-budget";
import AxeBuilder from "@axe-core/playwright";

async function login(page: Page, email: string) {
  await reserveLogin();
  await expect(page.getByRole("button", { name: "Войти", exact: true })).toBeEnabled({
    timeout: 45000,
  });
  await page.getByRole("button", { name: "Войти", exact: true }).click();
  await page.getByLabel("Email", { exact: true }).fill(email);
  await page.getByRole("dialog").getByRole("button", { name: "Войти", exact: true }).click();
  await expect(page.getByRole("button", { name: "Выйти", exact: true })).toBeVisible();
}

test("public brief has working materials navigation, persistent bookmarks and accessible layouts", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  const feed = await page.request.get(
    `/api/v1/projects?q=${encodeURIComponent("Айдентика для кофейного бренда")}`,
  );
  const project = (await feed.json()).data.find(
    (item: { title: string }) => item.title === "Айдентика для кофейного бренда",
  );
  expect(project).toBeTruthy();
  await page.goto(`/projects/${project.id}`, { waitUntil: "domcontentloaded" });
  await expect(page.locator("#project-title")).toHaveText(project.title);
  await expect(page.locator(".project-checklist li")).toHaveCount(project.deliverables.length);
  await expect(page.locator(".project-material-empty")).toContainText(
    "Пока без дополнительных материалов",
  );
  await page.getByRole("button", { name: "Сохранить проект", exact: true }).click();
  await page.reload({ waitUntil: "domcontentloaded" });
  await expect(
    page.getByRole("button", { name: "Убрать проект из сохранённых", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.getByRole("link", { name: "Материалы", exact: true }).click();
  await expect(page).toHaveURL(/#project-materials$/);
  await page
    .getByRole("button", { name: "Увеличить иллюстрацию: Характер бренда", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.getByRole("button", { name: "Следующая иллюстрация", exact: true }).click();
  await expect(page.getByRole("dialog").getByRole("heading")).toHaveText("Атмосфера места");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).not.toBeVisible();
  for (const width of [320, 390, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
  }
  const accessibility = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  expect(
    accessibility.violations.map((item) => ({
      id: item.id,
      nodes: item.nodes.map((node) => node.target),
    })),
  ).toEqual([]);
  await page.getByRole("button", { name: "Предложить цену и срок", exact: true }).click();
  await expect(page.getByRole("dialog").getByRole("heading")).toHaveText("С возвращением");
});

test("author keeps the draft when the client changes the brief and submits against the reviewed version", async ({
  browser,
}) => {
  const clientContext = await browser.newContext();
  const creatorContext = await browser.newContext();
  const client = await clientContext.newPage();
  const creator = await creatorContext.newPage();
  try {
    await client.goto("/", { waitUntil: "domcontentloaded" });
    await login(client, "client@mesh.local");
    const session = await (await client.request.get("/api/v1/session")).json();
    const deadline = new Date();
    deadline.setDate(deadline.getDate() + 30);
    const input = {
      title: `Бриф с версиями ${Date.now()}`,
      description: "Создать визуальную систему для независимого бренда.",
      category: "Дизайн",
      budget_minor: 5000000,
      currency: "RUB",
      deadline: deadline.toISOString().slice(0, 10),
      expected_result: "Исходники и гайд для команды.",
      deliverables: ["Логотип", "Упаковка"],
      requirements: ["Опыт работы с упаковкой"],
      skills: ["Брендинг"],
      reference_urls: ["https://example.com/brief.pdf"],
    };
    const created = await client.request.post("/api/v1/projects", {
      data: { project: input },
      headers: { "X-CSRF-Token": session.csrf_token, "Idempotency-Key": crypto.randomUUID() },
    });
    expect(created.status()).toBe(201);
    const project = await created.json();
    const url = `/projects/${project.id}`;
    await creator.goto(url, { waitUntil: "domcontentloaded" });
    await expect(creator.getByRole("button", { name: "Войти", exact: true })).toBeEnabled();
    let releaseRead!: () => void;
    let markReadReady!: () => void;
    const readHeld = new Promise<void>((resolve) => {
      releaseRead = resolve;
    });
    const readReady = new Promise<void>((resolve) => {
      markReadReady = resolve;
    });
    await creator.route("**/api/v1/projects?q=session-race-check", async (route) => {
      const response = await route.fetch();
      markReadReady();
      await readHeld;
      await route.fulfill({ response });
    });
    await creator.evaluate(() => {
      void fetch("/api/v1/projects?q=session-race-check");
    });
    await readReady;
    await login(creator, "design@mesh.local");
    const lateRead = creator.waitForResponse((response) =>
      response.url().includes("q=session-race-check"),
    );
    releaseRead();
    expect((await lateRead).headers()["set-cookie"]).toBeUndefined();
    expect((await (await creator.request.get("/api/v1/session")).json()).account).not.toBeNull();
    await creator.getByRole("button", { name: "Предложить цену и срок", exact: true }).click();
    await creator.getByLabel("Ваша цена, ₽", { exact: true }).fill("43210.55");
    await creator.getByLabel("Срок, дней", { exact: true }).fill("18");
    const approach = "Сначала исследую бренд, затем проверю две концепции на упаковке.";
    await creator.getByLabel("Ваш подход", { exact: true }).fill(approach);
    await expect(creator.locator(".proposal-summary")).toContainText("43 210,55");
    await creator.getByRole("button", { name: "Сохранить черновик", exact: true }).click();
    await creator.reload({ waitUntil: "domcontentloaded" });
    await expect(creator.getByLabel("Ваш подход", { exact: true })).toHaveValue(approach);
    await expect(creator.getByLabel("Ваша цена, ₽", { exact: true })).toHaveValue("43210.55");
    await creator.getByRole("button", { name: "К брифу", exact: true }).click();
    await expect(creator).not.toHaveURL(/proposal=new/);
    await creator.getByRole("button", { name: "Предложить цену и срок", exact: true }).click();
    await expect(creator.getByLabel("Ваш подход", { exact: true })).toHaveValue(approach);
    const sample = {
      name: "concept.png",
      mimeType: "image/png",
      buffer: Buffer.from(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCJkAAAAASUVORK5CYII=",
        "base64",
      ),
    };
    await creator.getByLabel("Прикрепить пример работы", { exact: true }).setInputFiles(sample);
    await expect(creator.locator(".proposal-file")).toContainText("concept.png");
    await creator.getByRole("button", { name: "Удалить пример работы", exact: true }).click();
    await expect(creator.locator(".proposal-file")).not.toBeVisible();
    await creator.getByLabel("Прикрепить пример работы", { exact: true }).setInputFiles(sample);
    await expect(creator.locator(".proposal-file")).toContainText("concept.png");
    for (const width of [320, 390, 768, 1024, 1440]) {
      await creator.setViewportSize({ width, height: 900 });
      expect(await creator.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
    }
    const updated = await client.request.patch(`/api/v1/projects/${project.id}`, {
      data: {
        project: { ...input, expected_result: "Исходники, гайд и адаптации для печати." },
        version: project.lock_version,
      },
      headers: { "X-CSRF-Token": session.csrf_token, "Idempotency-Key": crypto.randomUUID() },
    });
    expect(updated.status()).toBe(200);
    await creator.getByRole("checkbox").check();
    await creator.getByRole("button", { name: "Отправить предложение", exact: true }).click();
    await expect(creator.getByText("Бриф обновлён до v2", { exact: true })).toBeVisible();
    await expect(creator.getByLabel("Ваш подход", { exact: true })).toHaveValue(approach);
    await expect(creator.getByLabel("Ваша цена, ₽", { exact: true })).toHaveValue("43210.55");
    await expect(creator.getByLabel("Срок, дней", { exact: true })).toHaveValue("18");
    await expect(
      creator.getByRole("button", { name: "Отправить предложение", exact: true }),
    ).toBeDisabled();
    await creator.getByRole("button", { name: "Я изучил новую версию", exact: true }).click();
    const accessibility = await new AxeBuilder({ page: creator })
      .include(".project-terms")
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(
      accessibility.violations.map((item) => ({
        id: item.id,
        nodes: item.nodes.map((node) => node.target),
      })),
    ).toEqual([]);
    await creator.getByRole("checkbox").check();
    await creator.getByRole("button", { name: "Отправить предложение", exact: true }).click();
    await expect(creator.getByText("Ваше предложение отправлено", { exact: true })).toBeVisible();
    const detail = await (await creator.request.get(`/api/v1/projects/${project.id}`)).json();
    expect(detail.proposals).toHaveLength(1);
    expect(detail.proposals[0]).toMatchObject({
      brief_version: 2,
      price_minor: 4321055,
      delivery_days: 18,
      message: approach,
      example: { filename: "concept.png", content_type: "image/png" },
    });
    const creatorSession = await (await creator.request.get("/api/v1/session")).json();
    const draftKey = `mesh:proposal-draft:v1:${creatorSession.account.id}:${project.id}`;
    expect(await creator.evaluate((key) => localStorage.getItem(key), draftKey)).toBeNull();
    expect(detail.brief_history.at(-1).changed_fields).toEqual(["expected_result"]);
    await client.goto(url, { waitUntil: "domcontentloaded" });
    await client.getByRole("button", { name: /Посмотреть предложение Марк Соколов/ }).click();
    await expect(client.getByRole("button", { name: "Выбрать автора", exact: true })).toBeEnabled();
    await expect(client.locator(".owner-drawer .owner-example")).toContainText("concept.png");
    const download = await client.request.get(
      `/api/v1/projects/${project.id}/proposal_examples/${detail.proposals[0].example.id}/download`,
    );
    expect([200, 409]).toContain(download.status());
    if (download.status() === 200) expect(await download.body()).toEqual(sample.buffer);
    await client.getByRole("link", { name: "Обзор", exact: true }).click();
    await expect(client.locator(".project-materials a")).toHaveAttribute(
      "href",
      input.reference_urls[0],
    );
  } finally {
    await clientContext.close();
    await creatorContext.close();
  }
});
