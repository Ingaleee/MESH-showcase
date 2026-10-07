"use client";

import { useEffect, useRef } from "react";
import Image from "next/image";
import Link from "next/link";
import { ArrowRight, Search } from "lucide-react";
import gsap from "gsap";
import { useReducedMotion } from "motion/react";
import type { Project } from "@/lib/api";
import { imagePath } from "@/lib/home-content";
import { CreateProjectButton } from "../create-project-button";
import { EditorialAvatar } from "./editorial-avatar";

export function HomeHero({ projects }: { projects: Project[] }) {
  const root = useRef<HTMLElement>(null);
  const reducedMotion = useReducedMotion();

  useEffect(() => {
    if (reducedMotion) return;
    const context = gsap.context(() => {
      gsap.from(".collage-layer", {
        y: 24,
        opacity: 0,
        duration: 1,
        stagger: 0.09,
        ease: "power3.out",
      });
    }, root);
    return () => context.revert();
  }, [reducedMotion]);

  function destination(category: string) {
    const project = projects.find((item) => item.category === category);
    return project ? `/projects/${project.id}` : "/creators";
  }

  return (
    <section className="home-hero" ref={root} aria-labelledby="home-title">
      <div className="home-hero-copy">
        <span className="home-eyebrow">
          ИДЕИ <i /> ЛЮДИ <i /> РЕАЛЬНЫЕ РЕЗУЛЬТАТЫ
        </span>
        <h1 id="home-title">
          Найдите людей,
          <br />
          с которыми идеи
          <br />
          доходят <em>до результата.</em>
        </h1>
        <p>
          MESH — место, где независимые авторы помогают воплощать ваши идеи. Тексты, дизайн, видео,
          разработка и маркетинг.
        </p>
        <div className="home-hero-actions">
          <CreateProjectButton className="mesh-button mesh-button-dark mesh-button-glow" />
          <Link href="/creators" className="mesh-button mesh-button-light">
            <Search size={20} /> Найти автора
          </Link>
        </div>
        <div className="home-community">
          <div className="avatar-stack">
            {[0, 1, 2, 3].map((index) => (
              <EditorialAvatar key={index} index={index} />
            ))}
          </div>
          <div>
            <strong>Разные таланты. Общая цель.</strong>
            <span>Создавать то, что имеет значение.</span>
          </div>
        </div>
      </div>
      <div className="hero-collage">
        <div className="collage-backdrop" aria-hidden="true" />
        <svg className="collage-orbits" viewBox="0 0 620 580" aria-hidden="true">
          <ellipse cx="324" cy="296" rx="295" ry="117" transform="rotate(-46 324 296)" />
          <ellipse cx="337" cy="278" rx="288" ry="110" transform="rotate(-64 337 278)" />
          <circle cx="552" cy="69" r="4" />
          <circle cx="84" cy="494" r="4" />
        </svg>
        <span className="collage-note collage-layer" aria-hidden="true">
          Ideas
          <br />
          <span>connect</span>
          <br />
          <span>people.</span>
        </span>
        <div className="collage-portrait collage-layer">
          <Image
            src={imagePath("hero-portrait")}
            alt="Творческий взгляд: портрет автора"
            fill
            priority
            sizes="(max-width: 700px) 60vw, 360px"
            quality={85}
          />
          <span className="portrait-note">INDEPENDENT MINDS.</span>
        </div>
        <div className="collage-glass collage-layer" aria-hidden="true">
          <Image src={imagePath("category-design")} alt="" fill sizes="200px" quality={80} />
        </div>
        <Link href={destination("Дизайн")} className="collage-card collage-design collage-layer">
          <span className="collage-tag">Дизайн</span>
          <div className="collage-card-image">
            <Image src={imagePath("category-design")} alt="" fill sizes="140px" />
          </div>
          <span className="collage-card-title">
            Идея обретает
            <br />
            свой характер
          </span>
          <span className="round-arrow">
            <ArrowRight size={14} />
          </span>
        </Link>
        <Link
          href={destination("Разработка")}
          className="collage-card collage-development collage-layer"
        >
          <Image src={imagePath("category-development")} alt="" fill sizes="250px" />
          <div className="collage-dark-caption">
            <span className="collage-tag">Разработка</span>
            <span className="collage-card-title">
              Продукты, которыми
              <br />
              хочется пользоваться
            </span>
          </div>
          <span className="round-arrow">
            <ArrowRight size={14} />
          </span>
        </Link>
        <Link href={destination("Видео")} className="collage-card collage-film collage-layer">
          <span className="collage-tag">Видео</span>
          <div className="collage-card-image">
            <Image src={imagePath("mountain-film")} alt="" fill sizes="220px" />
            <span className="film-symbol" aria-hidden="true">
              ↗
            </span>
          </div>
          <span className="collage-card-title">
            Истории, которые
            <br />
            хочется досмотреть
          </span>
          <span className="round-arrow">
            <ArrowRight size={14} />
          </span>
        </Link>
        <Link href={destination("Тексты")} className="collage-card collage-writing collage-layer">
          <span className="collage-tag">Тексты</span>
          <div className="collage-card-image">
            <Image src={imagePath("category-texts")} alt="" fill sizes="160px" />
          </div>
          <span className="collage-card-title">
            Слова, которые
            <br />
            находят отклик
          </span>
          <span className="round-arrow">
            <ArrowRight size={14} />
          </span>
        </Link>
        <span className="collage-note-bottom collage-layer" aria-hidden="true">
          Большие идеи
          <br />
          начинаются с людей.
        </span>
      </div>
    </section>
  );
}
