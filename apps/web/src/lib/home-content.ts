import { ChartNoAxesColumn, Code2, Layers2, LayoutGrid, PenLine, Video } from "lucide-react";

export const disciplines = [
  {
    name: "Тексты",
    slug: "texts",
    description: "Статьи, сценарии,\nистории со смыслом",
    image: "category-texts",
    icon: PenLine,
    dark: false,
  },
  {
    name: "Дизайн",
    slug: "design",
    description: "Брендинг, сайты,\nформа и характер",
    image: "category-design",
    icon: Layers2,
    dark: true,
  },
  {
    name: "Видео",
    slug: "video",
    description: "Съёмка, монтаж,\nистории в движении",
    image: "category-video",
    icon: Video,
    dark: false,
  },
  {
    name: "Разработка",
    slug: "development",
    description: "Сайты, приложения,\nцифровые продукты",
    image: "category-development",
    icon: Code2,
    dark: true,
  },
  {
    name: "Маркетинг",
    slug: "marketing",
    description: "Стратегия, контент,\nновые возможности",
    image: "category-marketing",
    icon: ChartNoAxesColumn,
    dark: false,
  },
];

export const allDisciplines = { name: "Все проекты", icon: LayoutGrid };

export function projectImage(category: string) {
  if (category === "Дизайн") return "brand-still-life";
  if (category === "Видео") return "mountain-film";
  return disciplines.find((item) => item.name === category)?.image ?? "category-texts";
}

export function imagePath(name: string) {
  return `/images/home/${name}.png`;
}
