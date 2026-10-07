import { test, expect } from "@playwright/test";
import { reserveLogin } from "./support/login-budget";

test("creator search, combined filters, saved authors and shared profile links work", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/creators");
  const response = await page.request.get("/api/v1/creators");
  const { data: profiles } = await response.json();
  await expect(page.locator(".directory-card")).toHaveCount(profiles.length);
  await expect(page.getByRole("link", { name: "Авторы", exact: true })).toHaveAttribute(
    "aria-current",
    "page",
  );
  await page.keyboard.press("Control+k");
  const search = page.getByRole("textbox", { name: "Поиск авторов", exact: true });
  await expect(search).toBeFocused();
  await search.fill("Марк Соколов");
  await expect(page.locator(".directory-card")).toHaveCount(1);
  await expect(page.locator(".directory-card h2")).toHaveText("Марк Соколов");
  await page.getByRole("button", { name: "Сохранить автора: Марк Соколов", exact: true }).click();
  await page
    .getByRole("link", { name: "Открыть профиль автора Марк Соколов", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(page).toHaveURL(/profile=/);
  await page.reload();
  await expect(
    page.getByRole("dialog").getByRole("heading", { name: "Марк Соколов", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("dialog").getByRole("button", { name: "Автор сохранён", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toHaveCount(0);
  expect(new URL(page.url()).searchParams.has("profile")).toBe(false);
  await page.getByRole("button", { name: /Сохранённые/ }).click();
  await expect(page.locator(".directory-card")).toHaveCount(1);
  await page.getByRole("combobox", { name: "Бюджет за проект", exact: true }).selectOption("50");
  await expect(
    page.getByRole("heading", { name: "Здесь будут ваши находки", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Показать всех авторов", exact: true }).click();
  await expect(page.locator(".directory-card")).toHaveCount(profiles.length);
  await page.getByRole("button", { name: "Разработка", exact: true }).click();
  await expect(page.locator(".directory-card")).toHaveCount(1);
  await expect(page.locator(".directory-card h2")).toHaveText("Илья Мельников");
  await page.getByRole("button", { name: "Сбросить фильтры", exact: true }).click();
  await page.getByRole("combobox", { name: "Сортировка авторов", exact: true }).selectOption("low");
  await expect(page.locator(".directory-card h2").first()).toHaveText("Саша Волкова");
  await page.setViewportSize({ width: 390, height: 844 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page
    .getByRole("button", { name: "Убрать из сохранённых: Марк Соколов", exact: true })
    .click();
  await page.getByRole("button", { name: /Сохранённые/ }).click();
  await expect(
    page.getByRole("heading", { name: "Здесь будут ваши находки", exact: true }),
  ).toBeVisible();
});

test("filtered catalog retains the current author's profile when opening the editor", async ({
  page,
}) => {
  await page.goto("/creators");
  await page.getByRole("button", { name: "Войти", exact: true }).click();
  await page.getByLabel("Email", { exact: true }).fill("creator@mesh.local");
  await reserveLogin();
  await page.getByRole("dialog").getByRole("button", { name: "Войти", exact: true }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await page.getByRole("textbox", { name: "Поиск авторов", exact: true }).fill("React");
  await expect(page.locator(".directory-card")).toHaveCount(1);
  await page.getByRole("button", { name: "Мой профиль", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Специализация", exact: true })).toHaveValue(
    "Редактор и автор сложных историй",
  );
  await expect(
    page.getByRole("textbox", { name: "Навыки через запятую", exact: true }),
  ).toHaveValue("Редактура, UX-тексты, Интервью");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toHaveCount(0);
});
