import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Авторы — MESH",
  description:
    "Найдите автора по имени, навыкам и специализации. Сравните подход и стоимость, сохраните тех, с кем хотите создать следующий проект.",
};

export default function CreatorsLayout({ children }: { children: React.ReactNode }) {
  return children;
}
