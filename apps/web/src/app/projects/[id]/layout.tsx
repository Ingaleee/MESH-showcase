import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./project.css";
import "./proposal.css";
import "./owner.css";

export const metadata: Metadata = {
  title: "Бриф проекта — MESH",
  description: "Задача, материалы и условия проекта. Предложите свою стоимость и подход на MESH.",
};
export default function ProjectLayout({ children }: { children: ReactNode }) {
  return children;
}
