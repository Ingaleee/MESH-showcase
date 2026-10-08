"use client";
import Image from "next/image";
import Link from "next/link";
import { ArrowRight, Layers3 } from "lucide-react";
import { motion, useReducedMotion } from "motion/react";
import { formatMoney, type Project } from "@/lib/api";
import { briefDate, projectGallery } from "@/lib/project-content";
export function ProjectHero({
  project,
  proposalCount,
  composing = false,
  owner = false,
}: {
  project: Project;
  proposalCount: number;
  composing?: boolean;
  owner?: boolean;
}) {
  const gallery = projectGallery(project);
  const reducedMotion = useReducedMotion();
  return (
    <section className="project-hero" aria-labelledby="project-title">
      <motion.div
        className="project-hero-copy"
        initial={reducedMotion ? false : { opacity: 0, y: 15 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
      >
        <div className="project-hero-tags">
          <span className="project-pill">{project.category}</span>
          <span className={`project-open-state ${project.state !== "open" ? "is-closed" : ""}`}>
            <i />
            {project.state !== "open"
              ? "Автор выбран"
              : !project.accepting_proposals
                ? "Приём на паузе"
                : owner
                  ? "Принимаем предложения"
                  : "Открытый проект"}
          </span>
        </div>
        <h1 id="project-title">{project.title}</h1>
        <p className="project-intro">{project.description.split(/\n\s*\n/)[0]}</p>
        <div className="project-hero-client">
          <span className="project-client-mark" aria-hidden="true">
            {project.client.display_name.slice(0, 1)}
          </span>
          <div>
            <strong>{project.client.display_name}</strong>
            <span>Заказчик проекта</span>
          </div>
          <Link
            className="project-rounded-link"
            href={
              owner ? `/projects/${project.id}?view=overview#project-client` : "#project-client"
            }
          >
            О заказчике <ArrowRight size={15} />
          </Link>
        </div>
        {composing && (
          <div className="proposal-brief-conditions">
            <span>
              {formatMoney(project.budget_minor, project.currency)}
              <small>бюджет заказчика</small>
            </span>
            <span>
              {briefDate(project.deadline)}
              <small>дедлайн проекта</small>
            </span>
          </div>
        )}
      </motion.div>
      <motion.div
        className={`project-hero-art ${gallery.length === 1 ? "is-simple" : ""}`}
        aria-label="Иллюстрация проекта"
        role="img"
        initial={reducedMotion ? false : { opacity: 0, scale: 0.96 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.65, delay: 0.1 }}
      >
        <div className="project-art-orbit" />
        <div className="project-art-back">
          <Image
            src={gallery[1]?.src ?? gallery[0].src}
            alt=""
            fill
            sizes="(max-width: 750px) 70vw, 400px"
          />
        </div>
        <div className="project-art-main">
          <Image src={gallery[0].src} alt="" fill priority sizes="(max-width: 750px) 70vw, 420px" />
        </div>
        <div className="project-art-front">
          <Image src={gallery[2]?.src ?? gallery[0].src} alt="" fill sizes="200px" />
        </div>
        <span className="project-art-caption">
          FROM IDEA
          <br />
          <em>TO REALITY</em>
        </span>
      </motion.div>
      <div className="project-hero-stats">
        <Layers3 size={23} />
        <div>
          <strong>{proposalCount}</strong>
          <span>предложений</span>
        </div>
        <div>
          <strong>v{project.brief_version}</strong>
          <span>версия брифа</span>
        </div>
        <div>
          <span>Опубликован</span>
          <b>{briefDate(project.created_at)}</b>
        </div>
      </div>
    </section>
  );
}
