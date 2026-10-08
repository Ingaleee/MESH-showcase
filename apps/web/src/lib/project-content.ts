import type { Project } from "./api";
import { imagePath, projectImage } from "./home-content";

export function projectArtwork(project: Pick<Project, "title" | "category">) {
  return project.category === "Дизайн" && /кофе|кофейн|nora/i.test(project.title)
    ? "/images/projects/coffee-identity.png"
    : imagePath(projectImage(project.category));
}

export function projectGallery(project: Project) {
  return projectArtwork(project).startsWith("/images/projects/")
    ? [
        { src: "/images/projects/coffee-identity.png", title: "Характер бренда" },
        { src: "/images/projects/cafe-space.png", title: "Атмосфера места" },
        { src: "/images/projects/brand-paper.png", title: "Тактильность и форма" },
      ]
    : [{ src: projectArtwork(project), title: "Визуальное направление" }];
}

export function briefDate(value: string) {
  return new Date(value.length === 10 ? `${value}T00:00:00` : value).toLocaleDateString("ru-RU", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

export const briefFieldLabels: Record<string, string> = {
  title: "название",
  description: "задача",
  category: "направление",
  budget_minor: "бюджет",
  currency: "валюта",
  deadline: "дедлайн",
  expected_result: "ожидаемый результат",
  deliverables: "список работ",
  requirements: "требования",
  skills: "навыки",
  reference_urls: "материалы",
};
