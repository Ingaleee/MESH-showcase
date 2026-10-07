"use client";

import Image from "next/image";
import Link from "next/link";
import { ArrowRight, Bookmark } from "lucide-react";
import { motion, useReducedMotion } from "motion/react";
import { formatMoney, type Profile } from "@/lib/api";
import { creatorDirection, creatorVisuals } from "@/lib/creator-content";
import { imagePath } from "@/lib/home-content";
import { CreatorPortrait } from "./portrait";

export function CreatorCard({
  profile,
  index,
  saved,
  onSave,
  onOpen,
}: {
  profile: Profile;
  index: number;
  saved: boolean;
  onSave: () => void;
  onOpen: () => void;
}) {
  const reducedMotion = useReducedMotion();
  const name = profile.account.display_name;
  const href = `/creators?profile=${encodeURIComponent(profile.id)}`;

  return (
    <motion.article
      className="directory-card"
      id={`creator-${profile.id}`}
      initial={reducedMotion ? false : { opacity: 0, y: 12 }}
      whileInView={{ opacity: 1, y: 0 }}
      whileHover={reducedMotion ? undefined : { y: -3 }}
      viewport={{ once: true, amount: 0.1 }}
      transition={{ duration: 0.35, delay: Math.min(index, 3) * 0.04 }}
    >
      <Link
        href={href}
        className="directory-identity"
        aria-label={`Познакомиться с автором ${name}`}
        onClick={(event) => {
          if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
          event.preventDefault();
          onOpen();
        }}
      >
        <CreatorPortrait index={index} />
        <div>
          <span className="directory-direction">{creatorDirection(profile) ?? "Автор"}</span>
          <h2>{name}</h2>
          <p>{profile.headline}</p>
        </div>
      </Link>
      <p className="directory-bio">{profile.bio || "Знакомство начинается с вашей идеи."}</p>
      <div className="directory-skills" aria-label="Навыки автора">
        {profile.skills.slice(0, 3).map((skill) => (
          <span key={skill}>{skill}</span>
        ))}
      </div>
      <button
        className="directory-visuals"
        aria-label={`Посмотреть визуальное направление автора ${name}`}
        onClick={onOpen}
      >
        {creatorVisuals(profile).map((visual) => (
          <span key={visual}>
            <Image src={imagePath(visual)} alt="" fill sizes="(max-width: 700px) 110px, 95px" />
          </span>
        ))}
        <span className="directory-visuals-label">Визуальное направление · демо</span>
      </button>
      <div className="directory-card-footer">
        <strong>
          от {formatMoney(profile.rate_minor, profile.currency)}
          <small>за проект</small>
        </strong>
        <button
          className={`directory-icon-button ${saved ? "is-saved" : ""}`}
          aria-label={`${saved ? "Убрать из сохранённых" : "Сохранить автора"}: ${name}`}
          aria-pressed={saved}
          onClick={onSave}
        >
          <Bookmark size={18} fill={saved ? "currentColor" : "none"} />
        </button>
        <Link
          href={href}
          className="directory-icon-button directory-profile-link"
          aria-label={`Открыть профиль автора ${name}`}
          onClick={(event) => {
            if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
            event.preventDefault();
            onOpen();
          }}
        >
          <ArrowRight size={18} />
        </Link>
      </div>
    </motion.article>
  );
}
