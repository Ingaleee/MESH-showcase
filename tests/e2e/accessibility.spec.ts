import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("public pages and login meet automated WCAG 2.1 AA checks", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  for (const route of ["/", "/creators"]) {
    await page.goto(route);
    await expect(
      page.locator(route === "/" ? ".project-card" : ".directory-card").first(),
    ).toBeVisible();
    const result = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(
      result.violations.map((item) => ({
        id: item.id,
        nodes: item.nodes.map((node) => node.target),
      })),
    ).toEqual([]);
  }
  await page.locator(".directory-profile-link").first().click();
  await expect(page.getByRole("dialog")).toBeVisible();
  const creatorProfile = await new AxeBuilder({ page })
    .include("dialog")
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  expect(
    creatorProfile.violations.map((item) => ({
      id: item.id,
      nodes: item.nodes.map((node) => node.target),
    })),
  ).toEqual([]);
  await page.keyboard.press("Escape");
  await page.goto("/");
  await page.keyboard.press("Control+k");
  await expect(page.getByRole("textbox", { name: "Поиск проектов" })).toBeFocused();
  await page.getByRole("button", { name: "Войти", exact: true }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  const dialog = await new AxeBuilder({ page })
    .include("dialog")
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  expect(
    dialog.violations.map((item) => ({
      id: item.id,
      nodes: item.nodes.map((node) => node.target),
    })),
  ).toEqual([]);
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).not.toBeVisible();
});
