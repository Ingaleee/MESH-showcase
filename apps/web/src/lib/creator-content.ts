import type { Profile } from "./api";

export type CreatorDirection = "Тексты" | "Дизайн" | "Видео" | "Разработка" | "Маркетинг";

const directionRules: { direction: CreatorDirection; pattern: RegExp }[] = [
  {
    direction: "Разработка",
    pattern: /разработ|react|typescript|next\.?js|frontend|backend|программ/i,
  },
  { direction: "Видео", pattern: /режисс|монтаж|видео|съ[её]мк|motion|анимаци/i },
  { direction: "Маркетинг", pattern: /стратег|маркет|smm|реклам|аналитик|контент-план/i },
  { direction: "Тексты", pattern: /редактор|редактур|текст|копирайт|интервью|сценар/i },
  { direction: "Дизайн", pattern: /дизайн|айден|figma|иллюстр|типограф|арт-дир|обложк|брендинг/i },
];

const visualDirections: Record<CreatorDirection, string[]> = {
  Тексты: ["category-texts", "brand-still-life", "category-marketing"],
  Дизайн: ["category-design", "brand-still-life", "category-marketing"],
  Видео: ["mountain-film", "category-video", "hero-portrait"],
  Разработка: ["category-development", "category-design", "category-marketing"],
  Маркетинг: ["category-marketing", "brand-still-life", "category-development"],
};

// Until profiles have an explicit discipline, use their declared specialization and skills.
export function creatorDirection(profile: Profile): CreatorDirection | undefined {
  const specialization = [profile.headline, ...profile.skills].join(" ");
  return directionRules.find(({ pattern }) => pattern.test(specialization))?.direction;
}

export function creatorVisuals(profile: Profile) {
  return visualDirections[creatorDirection(profile) ?? "Дизайн"];
}

export function creatorIndex(profile: Profile, directory: Profile[]) {
  const index = directory.findIndex((item) => item.id === profile.id);
  if (index >= 0) return index;
  return [...profile.id].reduce((sum, character) => sum + character.charCodeAt(0), 0) % 6;
}

export function authorCount(count: number) {
  const last = count % 10;
  const lastTwo = count % 100;
  const noun =
    lastTwo >= 11 && lastTwo <= 14
      ? "авторов"
      : last === 1
        ? "автор"
        : last >= 2 && last <= 4
          ? "автора"
          : "авторов";
  return `${count} ${noun}`;
}
