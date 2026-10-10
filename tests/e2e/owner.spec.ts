import { test, expect, request, type APIRequestContext } from "@playwright/test";
import { reserveLogin } from "./support/login-budget";
import AxeBuilder from "@axe-core/playwright";

async function login(api: APIRequestContext, email: string) {
  await reserveLogin();
  const session = await (await api.get("/api/v1/session")).json();
  const result = await api.post("/api/v1/session", {
    data: { session: { email, password: "MeshDemo2026!" } },
    headers: { "X-CSRF-Token": session.csrf_token },
  });
  expect(result.status()).toBe(200);
  return (await result.json()).csrf_token as string;
}

function command(csrf: string, data: unknown) {
  return { data, headers: { "X-CSRF-Token": csrf, "Idempotency-Key": crypto.randomUUID() } };
}

async function publish(api: APIRequestContext, csrf: string) {
  const input = {
    title: `Выбор автора NORA ${Date.now()}-${crypto.randomUUID().slice(0, 5)}`,
    description: "Создать визуальную систему кофейного бренда с макетами для печати.",
    category: "Дизайн",
    budget_minor: 12000000,
    currency: "RUB",
    deadline: new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10),
    expected_result: "Редактируемые исходники и гайд.",
    deliverables: ["Логотип", "Упаковка"],
    requirements: ["Подготовка к печати"],
    skills: ["Брендинг"],
    reference_urls: [],
  };
  const response = await api.post("/api/v1/projects", command(csrf, { project: input }));
  expect(response.status()).toBe(201);
  return { project: await response.json(), input };
}

async function offer(
  api: APIRequestContext,
  csrf: string,
  id: string,
  price: number,
  days: number,
  version = 1,
) {
  const response = await api.post(
    `/api/v1/projects/${id}/propose`,
    command(csrf, {
      proposal: {
        price_minor: price,
        delivery_days: days,
        message: `Начну с исследования. Цена ${price}, срок ${days}. Передам исходники и печатные макеты.`,
        brief_version: version,
      },
    }),
  );
  expect(response.status()).toBe(201);
  return (await response.json()).id as string;
}

test("owner searches, sorts, saves, compares offers and uses the accessible drawer on five widths", async ({
  page,
  baseURL,
}) => {
  const csrf = await login(page.request, "client@mesh.local");
  const { project } = await publish(page.request, csrf);
  const accounts = [
    "design@mesh.local",
    "strategy@mesh.local",
    "illustration@mesh.local",
    "dev@mesh.local",
  ];
  for (const [index, email] of accounts.entries()) {
    const author = await request.newContext({ baseURL });
    try {
      await offer(
        author,
        await login(author, email),
        project.id,
        [9500000, 11000000, 8500000, 12000000][index],
        [18, 14, 21, 16][index],
      );
    } finally {
      await author.dispose();
    }
  }
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto(`/projects/${project.id}`);
  const cards = page.locator(".owner-proposal-card");
  await expect(cards).toHaveCount(4);
  await expect(page.getByRole("link", { name: /Предложения/ })).toHaveAttribute(
    "aria-current",
    "page",
  );
  await page.getByLabel("Сортировка предложений", { exact: true }).selectOption("price");
  await expect(cards.first()).toContainText("Никита Лис");
  await page.getByLabel("Сортировка предложений", { exact: true }).selectOption("days");
  await expect(cards.first()).toContainText("Даша Миронова");
  await page.getByLabel("Поиск по предложениям", { exact: true }).fill("типографика");
  await expect(cards).toHaveCount(1);
  await expect(cards.first()).toContainText("Марк Соколов");
  await page
    .getByRole("button", { name: "Сохранить предложение Марк Соколов, v1", exact: true })
    .click();
  await page.reload();
  await page.getByRole("button", { name: "Только избранные предложения", exact: true }).click();
  await expect(cards).toHaveCount(1);
  await expect(cards.first()).toContainText("Марк Соколов");
  await page.getByRole("button", { name: "Только избранные предложения", exact: true }).click();
  // Server filtering is asynchronous; compare stable cards after the full result arrives.
  await expect(cards).toHaveCount(4);
  const checks = page.getByRole("checkbox");
  await checks.nth(0).check();
  await checks.nth(1).check();
  await checks.nth(2).check();
  await checks.nth(3).click();
  await expect(checks.nth(3)).not.toBeChecked();
  await expect(page.getByRole("status")).toContainText("до трёх");
  await page.getByRole("button", { name: "Сравнить", exact: true }).click();
  await expect(page.locator(".owner-compare-columns article")).toHaveCount(3);
  await expect(page.getByRole("dialog")).toContainText("Версия брифа");
  await page.keyboard.press("Escape");
  for (const width of [320, 390, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    await page
      .getByRole("button", { name: "Посмотреть предложение Марк Соколов, v1", exact: true })
      .click();
    if (width <= 950)
      await expect(
        page.getByRole("dialog", { name: "Предложение автора", exact: true }),
      ).toBeVisible();
    else
      await expect(
        page.getByRole("complementary", { name: "Предложение Марк Соколов", exact: true }),
      ).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    if (width === 390 || width === 1440) {
      const result = await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
        .analyze();
      expect(
        result.violations.map((v) => ({ id: v.id, nodes: v.nodes.map((n) => n.target) })),
      ).toEqual([]);
    }
    await page.keyboard.press("Escape");
    await expect(page.locator(".owner-drawer, .owner-drawer-modal")).not.toBeVisible();
  }
  await page.getByRole("link", { name: "События", exact: true }).click();
  await expect(page.locator(".owner-events li")).toHaveCount(5);
  await page.getByRole("link", { name: "Работа", exact: true }).click();
  await expect(page.locator(".owner-work")).toContainText("Выберите автора");
});

test("owner cannot award an obsolete confirmation, can award while paused, and retains offers and fixed agreement terms", async ({
  page,
  baseURL,
}) => {
  const csrf = await login(page.request, "client@mesh.local");
  const { project, input } = await publish(page.request, csrf);
  const author = await request.newContext({ baseURL });
  const another = await request.newContext({ baseURL });
  try {
    const authorCsrf = await login(author, "design@mesh.local");
    const anotherCsrf = await login(another, "strategy@mesh.local");
    await offer(author, authorCsrf, project.id, 9500000, 18);
    await page.goto(`/projects/${project.id}`);
    await page
      .getByRole("button", { name: "Посмотреть предложение Марк Соколов, v1", exact: true })
      .click();
    await page.getByRole("button", { name: "Выбрать автора", exact: true }).click();
    await expect(page.getByRole("dialog")).toContainText("95 000");
    const revision = await page.request.patch(
      `/api/v1/projects/${project.id}`,
      command(csrf, {
        project: { ...input, expected_result: "Исходники, гайд и проверка на печати." },
        version: project.lock_version,
      }),
    );
    expect(revision.status()).toBe(200);
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "Начать работу", exact: true })
      .click();
    await expect(page.getByRole("dialog")).toContainText("Бриф изменился");
    await expect(
      page.getByRole("dialog").getByRole("button", { name: "Начать работу", exact: true }),
    ).toBeDisabled();
    await page.getByRole("button", { name: "Отмена", exact: true }).click();
    await expect(
      page.getByRole("button", { name: "К предыдущей версии брифа", exact: true }),
    ).toBeDisabled();
    await page.keyboard.press("Escape");
    const currentId = await offer(author, authorCsrf, project.id, 9700000, 17, 2);
    await page.getByRole("button", { name: "Обновить предложения", exact: true }).click();
    await expect(page.locator(".owner-proposal-card")).toHaveCount(2);
    await page.getByLabel("Версия предложений", { exact: true }).selectOption("old");
    await expect(page.locator(".owner-proposal-card")).toHaveCount(1);
    await page.getByLabel("Версия предложений", { exact: true }).selectOption("current");
    await expect(page.locator(".owner-proposal-card")).toHaveCount(1);
    await page.getByRole("button", { name: "Приостановить приём", exact: true }).click();
    await expect(
      page.getByRole("button", { name: "Возобновить приём", exact: true }),
    ).toBeVisible();
    const paused = await another.post(
      `/api/v1/projects/${project.id}/propose`,
      command(anotherCsrf, {
        proposal: {
          price_minor: 9900000,
          delivery_days: 20,
          message: "Проверка приёма на паузе.",
          brief_version: 2,
        },
      }),
    );
    expect(paused.status()).toBe(409);
    expect((await paused.json()).code).toBe("PROPOSALS_PAUSED");
    await page
      .getByRole("button", { name: "Посмотреть предложение Марк Соколов, v2", exact: true })
      .click();
    await page.getByRole("button", { name: "Выбрать автора", exact: true }).click();
    await page.getByRole("button", { name: "Отмена", exact: true }).click();
    let detail = await (await page.request.get(`/api/v1/projects/${project.id}`)).json();
    expect(detail.owner_context.award).toBeNull();
    await page.getByRole("button", { name: "Выбрать автора", exact: true }).click();
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "Начать работу", exact: true })
      .click();
    await expect(page).toHaveURL(/view=work/);
    await expect(page.locator(".owner-work")).toContainText("Марк Соколов");
    detail = await (await page.request.get(`/api/v1/projects/${project.id}`)).json();
    expect(detail.project.state).toBe("awarded");
    expect(detail.project.accepting_proposals).toBe(false);
    expect(detail.proposals).toHaveLength(2);
    expect(detail.owner_context.award.proposal_id).toBe(currentId);
    const agreement = await (
      await page.request.get(`/api/v1/engagements/${detail.owner_context.award.engagement_id}`)
    ).json();
    expect(agreement.terms).toMatchObject({
      brief_version: 2,
      price_minor: 9700000,
      delivery_days: 17,
      expected_result: "Исходники, гайд и проверка на печати.",
    });
    const guest = await request.newContext({ baseURL });
    try {
      const closedProject = await guest.get(`/api/v1/projects/${project.id}`);
      expect(closedProject.status()).toBe(403);
      expect((await closedProject.json()).code).toBe("FORBIDDEN");
    } finally {
      await guest.dispose();
    }
  } finally {
    await author.dispose();
    await another.dispose();
  }
});
