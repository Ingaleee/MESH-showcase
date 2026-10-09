"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ArrowRight, Bookmark, CalendarDays, X } from "lucide-react";
import { formatMoney, type Project, type Proposal } from "@/lib/api";
import { Modal } from "@/components/modal";
import { ProposalAvatar, ProposalExampleView, proposalTime } from "./owner-proposal-parts";

export function OwnerProposalDrawer({
  project,
  proposal,
  saved,
  onSave,
  onClose,
  onChoose,
}: {
  project: Project;
  proposal: Proposal;
  saved: boolean;
  onSave: () => void;
  onClose: () => void;
  onChoose: () => void;
}) {
  const [mobile, setMobile] = useState(false);
  const close = useRef<HTMLButtonElement>(null);
  const stale = proposal.brief_version !== project.brief_version;
  const canChoose = project.state === "open" && !stale;
  useEffect(() => {
    const media = matchMedia("(max-width: 950px)");
    const update = () => setMobile(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  useEffect(() => {
    if (mobile) return;
    const opener = document.activeElement;
    close.current?.focus({ preventScroll: true });
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !document.querySelector("dialog[open]")) onClose();
    };
    window.addEventListener("keydown", escape);
    return () => {
      window.removeEventListener("keydown", escape);
      if (opener instanceof HTMLElement && opener.isConnected)
        opener.focus({ preventScroll: true });
    };
  }, [mobile]);
  const content = (
    <>
      <div className="owner-drawer-person">
        <ProposalAvatar proposal={proposal} />
        <div>
          <h2>{proposal.creator.display_name}</h2>
          <p>{proposal.profile?.headline ?? "Автор на MESH"}</p>
          <span>Предложение к брифу v{proposal.brief_version}</span>
        </div>
      </div>
      {proposal.profile?.skills.length ? (
        <div className="owner-skill-list">
          {proposal.profile.skills.slice(0, 5).map((skill) => (
            <span key={skill}>{skill}</span>
          ))}
        </div>
      ) : null}
      <div className="owner-drawer-terms">
        <div>
          <span>Цена</span>
          <strong>{formatMoney(proposal.price_minor, project.currency)}</strong>
        </div>
        <div>
          <span>Срок</span>
          <strong>{proposal.delivery_days} дней</strong>
        </div>
        <button className="project-primary" disabled={!canChoose} onClick={onChoose}>
          {stale
            ? "К предыдущей версии брифа"
            : project.state !== "open"
              ? "Приём завершён"
              : "Выбрать автора"}
          <ArrowRight size={17} />
        </button>
      </div>
      {stale && (
        <p className="owner-notice">
          Бриф обновлён до v{project.brief_version}. Условия этого отклика относятся к предыдущей
          задаче.
        </p>
      )}
      <section className="owner-drawer-section">
        <div className="owner-section-title">
          <h3>Сообщение автора</h3>
          <time dateTime={proposal.created_at}>{proposalTime(proposal.created_at)}</time>
        </div>
        <p className="owner-full-message">{proposal.message}</p>
      </section>
      <section className="owner-drawer-section">
        <h3>Пример работы</h3>
        <ProposalExampleView projectId={project.id} proposal={proposal} large />
      </section>
      <section className="owner-drawer-section">
        <div className="owner-section-title">
          <h3>Об авторе</h3>
          {proposal.profile && (
            <Link href={`/creators?profile=${proposal.profile.id}`}>
              Профиль <ArrowRight size={14} />
            </Link>
          )}
        </div>
        <p className="owner-full-message">
          {proposal.profile?.bio ||
            "Автор пока не добавил описание опыта. Его подход к вашему проекту — в сообщении выше."}
        </p>
      </section>
      <div className="owner-drawer-footer">
        <button className="owner-outline" aria-pressed={saved} onClick={onSave}>
          <Bookmark size={16} fill={saved ? "currentColor" : "none"} />
          {saved ? "В избранных предложениях" : "Сохранить для выбора"}
        </button>
        <p>
          <CalendarDays size={14} />
          Срок — после согласования условий.
        </p>
      </div>
    </>
  );
  return mobile ? (
    <Modal title="Предложение автора" className="owner-drawer-modal" onClose={onClose}>
      {content}
    </Modal>
  ) : (
    <aside className="owner-drawer" aria-label={`Предложение ${proposal.creator.display_name}`}>
      <div className="owner-drawer-heading">
        <span>ПРЕДЛОЖЕНИЕ АВТОРА</span>
        <button ref={close} aria-label="Закрыть предложение" onClick={onClose}>
          <X size={20} />
        </button>
      </div>
      {content}
    </aside>
  );
}
