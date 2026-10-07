"use client";

import Image from "next/image";
import Link from "next/link";
import { Bookmark, CalendarDays, Wallet } from "lucide-react";
import { motion, useReducedMotion } from "motion/react";
import { formatMoney, type Project } from "@/lib/api";
import { projectArtwork } from "@/lib/project-content";

export function HomeProjectCard({
  project,
  saved,
  onSave,
  index,
}: {
  project: Project;
  saved: boolean;
  onSave: () => void;
  index: number;
}) {
  const reducedMotion = useReducedMotion();
  return (
    <motion.article
      className="home-project-card project-card"
      initial={reducedMotion ? false : { opacity: 0, y: 14 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.1 }}
      transition={{ duration: 0.35, delay: Math.min(index, 3) * 0.045 }}
    >
      <Link
        href={`/projects/${project.id}`}
        className="home-project-cover"
        aria-label={`Открыть проект: ${project.title}`}
        tabIndex={-1}
      >
        <Image
          src={projectArtwork(project)}
          alt=""
          fill
          sizes="(max-width: 600px) 90vw, (max-width: 1000px) 45vw, 300px"
        />
        <span className="home-cover-tag category-label">{project.category}</span>
      </Link>
      <div className="home-project-body">
        <Link href={`/projects/${project.id}`} className="home-project-title">
          <h3>{project.title}</h3>
        </Link>
        <p>{project.description}</p>
        <div className="home-project-meta">
          <strong>
            <Wallet size={15} />
            {formatMoney(project.budget_minor, project.currency)}
          </strong>
          <span>
            <CalendarDays size={16} />
            {new Date(`${project.deadline}T00:00:00`).toLocaleDateString("ru-RU", {
              day: "numeric",
              month: "short",
            })}
          </span>
        </div>
        <div className="home-project-client">
          <span className="home-client-avatar" aria-hidden="true">
            {project.client.display_name.slice(0, 1)}
          </span>
          <div>
            <strong>{project.client.display_name}</strong>
            <span>
              {project.state === "open" ? "Открытый проект" : "Автор выбран"} · бриф v
              {project.brief_version}
            </span>
          </div>
          <button
            className={`save-button ${saved ? "is-saved" : ""}`}
            aria-label={`${saved ? "Убрать из сохранённых" : "Сохранить проект"}: ${project.title}`}
            aria-pressed={saved}
            onClick={onSave}
          >
            <Bookmark size={18} fill={saved ? "currentColor" : "none"} />
          </button>
        </div>
      </div>
    </motion.article>
  );
}
