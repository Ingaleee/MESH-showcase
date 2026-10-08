"use client";

import { useState } from "react";
import { ArrowRight, Bookmark, Check, Copy, ShieldCheck } from "lucide-react";
import { formatMoney, type Project, type Proposal } from "@/lib/api";
import { briefDate } from "@/lib/project-content";
import { useSession } from "@/components/session-provider";

export function ProposalBox({
  project,
  proposals,
  saved,
  onSave,
  onCompose,
}: {
  project: Project;
  proposals: Proposal[];
  saved: boolean;
  onSave: () => void;
  onCompose: () => void;
}) {
  const { account, openLogin } = useSession();
  const current = proposals.find(
    (item) => item.creator.id === account?.id && item.brief_version === project.brief_version,
  );
  const [feedback, setFeedback] = useState("");
  async function copyLink() {
    try {
      await navigator.clipboard.writeText(location.href);
      setFeedback("Ссылка скопирована");
    } catch {
      setFeedback("Не удалось скопировать ссылку. Её можно взять из адресной строки.");
    }
  }
  return (
    <div className="project-terms" id="project-proposal">
      <div className="project-budget-label">
        <span>Бюджет проекта</span>
        <span className="project-pill">{project.currency}</span>
      </div>
      <h2>{formatMoney(project.budget_minor, project.currency)}</h2>
      <p className="project-budget-note">Предложите свою стоимость и подход к задаче.</p>
      <div className="project-condition-grid">
        <div>
          <span>Дедлайн</span>
          <strong>{briefDate(project.deadline)}</strong>
        </div>
        <div>
          <span>Условия</span>
          <strong>Бриф v{project.brief_version}</strong>
        </div>
      </div>
      {current ? (
        <div className="project-proposal-success" role="status">
          <Check size={22} />
          <strong>Ваше предложение отправлено</strong>
          <span>
            Вы предложили {formatMoney(current.price_minor, project.currency)} ·{" "}
            {current.delivery_days} дн.
          </span>
        </div>
      ) : project.state !== "open" ? (
        <p className="project-proposal-success">Автор выбран. Приём предложений завершён.</p>
      ) : !project.accepting_proposals ? (
        <p className="project-proposal-success">Заказчик приостановил приём предложений.</p>
      ) : !account ? (
        <button
          className="project-primary"
          onClick={() => {
            onCompose();
            openLogin();
          }}
        >
          Предложить цену и срок <ArrowRight size={18} />
        </button>
      ) : (
        <button className="project-primary" onClick={onCompose}>
          Предложить цену и срок <ArrowRight size={18} />
        </button>
      )}
      <div className="project-save-share">
        <button
          onClick={onSave}
          aria-pressed={saved}
          aria-label={saved ? "Убрать проект из сохранённых" : "Сохранить проект"}
        >
          <Bookmark size={18} fill={saved ? "currentColor" : "none"} />
          {saved ? "Сохранено" : "Сохранить"}
        </button>
        <button
          onClick={() => {
            void copyLink();
          }}
          aria-label="Скопировать ссылку на проект"
        >
          <Copy size={17} />
        </button>
      </div>
      <span className="project-action-feedback" role="status">
        {feedback}
      </span>
      <div className="project-terms-footnote">
        <ShieldCheck size={17} />
        <span>Условия выбранного предложения фиксируются в соглашении.</span>
      </div>
    </div>
  );
}
