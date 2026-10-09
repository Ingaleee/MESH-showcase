"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import {
  ArrowRight,
  Check,
  ChevronRight,
  CirclePause,
  CirclePlay,
  GitCompareArrows,
  Layers3,
  Pencil,
  RefreshCw,
  X,
} from "lucide-react";
import { formatMoney, type ProjectDetail, type Proposal } from "@/lib/api";
import { useOwnerProposals } from "./use-owner-proposals";
import { briefDate } from "@/lib/project-content";
import { useCommand } from "@/lib/use-command";
import { Modal } from "@/components/modal";
import { ProjectForm } from "@/components/project-form";
import { BriefContent } from "./brief-content";
import { ProjectHero } from "./project-hero";
import { OwnerProposalList, type ProposalSort } from "./owner-proposal-list";
import { OwnerProposalDrawer } from "./owner-proposal-drawer";
import { ProposalAvatar, ProposalExampleView, proposalTime } from "./owner-proposal-parts";

type OwnerTab = "overview" | "proposals" | "work" | "events";
const eventLabels: Record<string, string> = {
  published: "Проект опубликован",
  brief_revised: "Бриф обновлён",
  proposal_received: "Получено предложение",
  intake_paused: "Приём предложений приостановлен",
  intake_resumed: "Приём предложений возобновлён",
  awarded: "Автор выбран, условия зафиксированы",
};
const workLabels: Record<string, string> = {
  agreed: "Условия согласованы",
  in_progress: "В работе",
  submitted: "Результат на приёмке",
  accepted: "Результат принят",
  cancelled: "Работа отменена",
};

export function OwnerProject({
  detail,
  refresh,
}: {
  detail: ProjectDetail;
  refresh: () => Promise<void>;
}) {
  const { project, owner_context: context } = detail;
  const router = useRouter();
  const search = useSearchParams();
  const requested = search.get("view");
  const tab: OwnerTab =
    requested === "overview" || requested === "work" || requested === "events"
      ? requested
      : "proposals";
  const [editing, setEditing] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<ProposalSort>("newest");
  const [versionFilter, setVersionFilter] = useState("all");
  const [savedOnly, setSavedOnly] = useState(false);
  const [shortlist, setShortlist] = useState<string[]>([]);
  const [compareIds, setCompareIds] = useState<string[]>([]);
  const [compareOpen, setCompareOpen] = useState(false);
  const [feedback, setFeedback] = useState("");
  const [confirmation, setConfirmation] = useState<{
    proposal: Proposal;
    version: number;
    title: string;
  } | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const award = useCommand();
  const intake = useCommand();
  const shortlistKey = `mesh:proposal-shortlist:v1:${project.client.id}:${project.id}`;
  const offers = useOwnerProposals(detail, {
    query,
    sort,
    version: versionFilter,
    ids: savedOnly ? shortlist : null,
  });
  const proposals = offers.cache;
  const selected = proposals.find((item) => item.id === selectedId) ?? null;
  const compared = proposals.filter((item) => compareIds.includes(item.id));
  const chosen = proposals.find((item) => item.id === context?.award?.proposal_id);
  const workLink = context?.award ? `/workspace?engagement=${context.award.engagement_id}` : null;
  const closeDrawer = useCallback(() => setSelectedId(null), []);
  function setTab(next: OwnerTab) {
    const params = new URLSearchParams(search.toString());
    params.set("view", next);
    params.delete("proposal");
    router.push(`/projects/${project.id}?${params}`, { scroll: false });
    closeDrawer();
  }
  useEffect(() => {
    try {
      const ids: unknown = JSON.parse(localStorage.getItem(shortlistKey) ?? "[]");
      if (Array.isArray(ids))
        setShortlist(ids.filter((item): item is string => typeof item === "string").slice(0, 100));
    } catch {
      setShortlist([]);
    }
  }, [shortlistKey]);
  useEffect(() => {
    const update = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    const timer = setInterval(update, 30000);
    window.addEventListener("focus", update);
    return () => {
      clearInterval(timer);
      window.removeEventListener("focus", update);
    };
  }, [refresh]);
  function toggleSave(id: string) {
    if (!shortlist.includes(id) && shortlist.length >= 100) {
      setFeedback("Можно сохранить до 100 предложений.");
      return;
    }
    const next = shortlist.includes(id)
      ? shortlist.filter((item) => item !== id)
      : [...shortlist, id];
    setShortlist(next);
    try {
      localStorage.setItem(shortlistKey, JSON.stringify(next));
      setFeedback(
        next.includes(id)
          ? "Предложение сохранено в этом браузере"
          : "Предложение убрано из избранных",
      );
    } catch {
      setFeedback("Браузер не разрешил сохранить избранные предложения.");
    }
  }
  function toggleCompare(id: string) {
    if (compareIds.includes(id)) setCompareIds((ids) => ids.filter((item) => item !== id));
    else if (compareIds.length < 3) setCompareIds((ids) => [...ids, id]);
    else {
      setFeedback("Для сравнения можно выбрать до трёх предложений.");
      return;
    }
    setFeedback("");
  }
  function confirm(proposal: Proposal) {
    award.clearError();
    setConfirmation({ proposal, version: project.brief_version, title: project.title });
  }
  async function choose() {
    if (!confirmation || confirmation.version !== project.brief_version || project.state !== "open")
      return;
    try {
      await award.execute(`/projects/${project.id}/award`, {
        proposal_id: confirmation.proposal.id,
        brief_version: confirmation.version,
      });
      setConfirmation(null);
      setCompareIds([]);
      closeDrawer();
      await refresh();
      setTab("work");
    } catch {
      await refresh();
    }
  }
  async function changeIntake() {
    try {
      await intake.execute(`/projects/${project.id}/intake`, {
        accepting_proposals: !project.accepting_proposals,
        version: project.lock_version,
      });
      await refresh();
    } catch {
      await refresh();
    }
  }
  const visible = offers.items;
  return (
    <div
      className={`project-page owner-page ${selected && tab === "proposals" ? "has-drawer" : ""}`}
    >
      <div className="owner-main">
        <nav className="project-breadcrumbs" aria-label="Хлебные крошки">
          <Link href="/#projects">Проекты</Link>
          <ChevronRight size={13} />
          <span>{project.title}</span>
        </nav>
        <div className="owner-hero">
          <ProjectHero project={project} proposalCount={detail.proposal_count} owner />
        </div>
        <div className="owner-management">
          <div className="owner-management-info">
            <span className="owner-kicker">ВАШ ПРОЕКТ</span>
            <strong>{formatMoney(project.budget_minor, project.currency)}</strong>
            <span>
              Дедлайн {briefDate(project.deadline)} · бриф v{project.brief_version}
            </span>
          </div>
          {project.state === "open" && (
            <div className="owner-management-actions">
              <button
                className="owner-outline"
                onClick={() => {
                  setTab("overview");
                  setEditing(true);
                }}
              >
                <Pencil size={15} />
                Редактировать бриф
              </button>
              <button
                className="owner-text-button"
                disabled={intake.pending}
                onClick={() => {
                  void changeIntake();
                }}
              >
                {project.accepting_proposals ? <CirclePause size={16} /> : <CirclePlay size={16} />}
                {intake.pending
                  ? "Обновляем…"
                  : project.accepting_proposals
                    ? "Приостановить приём"
                    : "Возобновить приём"}
              </button>
            </div>
          )}
          <button
            className="owner-refresh"
            aria-label="Обновить предложения"
            disabled={refreshing}
            onClick={async () => {
              setRefreshing(true);
              await refresh();
              setRefreshing(false);
            }}
          >
            <RefreshCw size={17} className={refreshing ? "proposal-spinner" : ""} />
          </button>
        </div>
        {intake.error && (
          <p className="error" role="alert">
            {intake.error}
          </p>
        )}
        {!project.accepting_proposals && project.state === "open" && (
          <p className="owner-notice">
            <CirclePause size={17} />
            Приём на паузе. Полученные предложения доступны для сравнения и выбора.
          </p>
        )}
        {context?.award && tab !== "work" && (
          <div className="owner-award-banner">
            <Check size={19} />
            <div>
              <strong>Автор выбран: {context.award.creator_name}</strong>
              <span>Условия предложения зафиксированы в соглашении.</span>
            </div>
            <Link href={workLink!}>
              Перейти к работе <ArrowRight size={16} />
            </Link>
          </div>
        )}
        <nav className="owner-tabs" aria-label="Разделы вашего проекта">
          {(
            [
              ["overview", "Обзор"],
              ["proposals", "Предложения"],
              ["work", "Работа"],
              ["events", "События"],
            ] as const
          ).map(([value, label]) => (
            <Link
              key={value}
              href={`/projects/${project.id}?view=${value}`}
              aria-current={tab === value ? "page" : undefined}
              onClick={(event) => {
                event.preventDefault();
                setTab(value);
              }}
            >
              {label}
              {value === "proposals" && <span>{proposals.length}</span>}
              {value === "work" && context?.award && <i />}
            </Link>
          ))}
        </nav>
        {tab === "proposals" && (
          <OwnerProposalList
            project={project}
            proposals={proposals}
            visible={visible}
            query={query}
            setQuery={setQuery}
            sort={sort}
            setSort={setSort}
            versionFilter={versionFilter}
            setVersionFilter={setVersionFilter}
            savedOnly={savedOnly}
            setSavedOnly={setSavedOnly}
            shortlist={shortlist}
            toggleSave={toggleSave}
            selectedId={selectedId}
            open={setSelectedId}
            compareIds={compareIds}
            toggleCompare={toggleCompare}
            compareFeedback={feedback}
            totalCount={detail.proposal_count}
            currentCount={detail.current_proposal_count}
            matchedCount={offers.matchedCount}
            hasMore={offers.nextCursor !== null}
            loading={offers.loading}
            error={offers.error}
            loadMore={() => void offers.loadMore()}
          />
        )}
        {tab === "overview" && (
          <article className="project-brief owner-overview">
            <BriefContent project={project} history={detail.brief_history} />
            <section id="project-client" className="project-section">
              <h2>Заказчик проекта</h2>
              <p className="project-prose">{project.client.display_name}</p>
            </section>
          </article>
        )}
        {tab === "events" && (
          <section className="owner-events">
            <span className="owner-kicker">ИСТОРИЯ СОТРУДНИЧЕСТВА</span>
            <h2>События проекта</h2>
            <ol>
              {context?.events.map((event) => (
                <li key={event.id}>
                  <span className="owner-event-dot" />
                  <div>
                    <strong>
                      {eventLabels[event.kind] ?? event.kind}
                      {event.actor_name ? ` · ${event.actor_name}` : ""}
                    </strong>
                    <p>
                      {proposalTime(event.created_at)}
                      {event.brief_version ? ` · бриф v${event.brief_version}` : ""}
                    </p>
                  </div>
                </li>
              ))}
            </ol>
            <p className="owner-illustration-note">
              Последние 50 событий. История предложений и условий сохраняется.
            </p>
          </section>
        )}
        {tab === "work" && (
          <section className="owner-work">
            <span className="owner-kicker">ОТ ВЫБОРА — К РЕЗУЛЬТАТУ</span>
            {chosen && context?.award ? (
              <>
                <h2>Автор выбран</h2>
                <p>
                  {workLabels[context.award.engagement_state] ?? "Соглашение создано"}.
                  Договорённости доступны в рабочем пространстве.
                </p>
                <div className="owner-work-card">
                  <ProposalAvatar proposal={chosen} />
                  <div>
                    <h3>{chosen.creator.display_name}</h3>
                    <span>{chosen.profile?.headline ?? "Автор проекта"}</span>
                  </div>
                  <strong>{formatMoney(chosen.price_minor, project.currency)}</strong>
                  <span>{chosen.delivery_days} дней</span>
                </div>
                <div className="owner-work-summary">
                  <span>
                    <Check size={17} />
                    Цена и срок зафиксированы
                  </span>
                  <span>
                    <Layers3 size={17} />
                    Бриф v{chosen.brief_version}
                  </span>
                </div>
                <Link className="project-primary" href={workLink!}>
                  Перейти к работе <ArrowRight size={18} />
                </Link>
              </>
            ) : (
              <>
                <h2>Выберите автора для проекта</h2>
                <p>
                  Сравните предложения и выберите подход. После подтверждения здесь появятся
                  согласованные условия и переход к работе.
                </p>
                <button className="project-primary" onClick={() => setTab("proposals")}>
                  Посмотреть предложения <ArrowRight size={18} />
                </button>
              </>
            )}
          </section>
        )}
        {tab === "proposals" && compareIds.length > 0 && (
          <div className="owner-compare-bar" role="region" aria-label="Выбранные предложения">
            <GitCompareArrows size={20} />
            <span>Выбрано {compared.length} из 3</span>
            <button
              className="project-primary"
              disabled={compared.length < 2}
              onClick={() => setCompareOpen(true)}
            >
              Сравнить <ArrowRight size={15} />
            </button>
            <button
              className="owner-compare-clear"
              aria-label="Очистить сравнение"
              onClick={() => setCompareIds([])}
            >
              <X size={17} />
            </button>
          </div>
        )}
      </div>
      {selected && tab === "proposals" && (
        <OwnerProposalDrawer
          key={selected.id}
          project={project}
          proposal={selected}
          saved={shortlist.includes(selected.id)}
          onSave={() => toggleSave(selected.id)}
          onClose={closeDrawer}
          onChoose={() => confirm(selected)}
        />
      )}
      {compareOpen && (
        <Modal
          title="Сравнение предложений"
          className="owner-compare-modal"
          onClose={() => setCompareOpen(false)}
        >
          <p className="owner-modal-intro">
            Сравните состав работ и подход. Срок указан после согласования условий.
          </p>
          <div className="owner-compare-columns">
            {compared.map((proposal) => (
              <article key={proposal.id}>
                <ProposalAvatar proposal={proposal} />
                <h3>{proposal.creator.display_name}</h3>
                <p className="owner-compare-headline">
                  {proposal.profile?.headline ?? "Автор на MESH"}
                </p>
                <dl>
                  <div>
                    <dt>Стоимость</dt>
                    <dd>{formatMoney(proposal.price_minor, project.currency)}</dd>
                  </div>
                  <div>
                    <dt>Срок</dt>
                    <dd>{proposal.delivery_days} дней</dd>
                  </div>
                  <div>
                    <dt>Версия брифа</dt>
                    <dd>
                      v{proposal.brief_version}
                      {proposal.brief_version !== project.brief_version
                        ? " · предыдущая"
                        : " · текущая"}
                    </dd>
                  </div>
                </dl>
                <h4>Подход</h4>
                <p className="owner-full-message">{proposal.message}</p>
                <h4>Пример работы</h4>
                <ProposalExampleView projectId={project.id} proposal={proposal} />
                <button
                  className="owner-outline"
                  onClick={() => {
                    setCompareOpen(false);
                    setSelectedId(proposal.id);
                  }}
                >
                  Посмотреть детали <ArrowRight size={16} />
                </button>
              </article>
            ))}
          </div>
        </Modal>
      )}
      {confirmation && (
        <Modal
          title={`Начать работу с ${confirmation.proposal.creator.display_name}?`}
          className="owner-confirm-modal"
          onClose={() => {
            if (!award.pending) setConfirmation(null);
          }}
        >
          <span className="owner-kicker">УСЛОВИЯ БУДУТ ЗАФИКСИРОВАНЫ</span>
          <h3>{confirmation.title}</h3>
          <div className="owner-confirm-person">
            <ProposalAvatar proposal={confirmation.proposal} />
            <div>
              <strong>{confirmation.proposal.creator.display_name}</strong>
              <span>{confirmation.proposal.profile?.headline ?? "Автор на MESH"}</span>
            </div>
          </div>
          <dl className="owner-confirm-terms">
            <div>
              <dt>Стоимость</dt>
              <dd>{formatMoney(confirmation.proposal.price_minor, project.currency)}</dd>
            </div>
            <div>
              <dt>Срок</dt>
              <dd>{confirmation.proposal.delivery_days} дней</dd>
            </div>
            <div>
              <dt>Версия брифа</dt>
              <dd>v{confirmation.version}</dd>
            </div>
          </dl>
          <p className="owner-modal-intro">
            После подтверждения создаётся соглашение с этими условиями. Приём предложений
            завершается; остальные отклики остаются в истории. Оплата этим действием не
            производится.
          </p>
          {confirmation.version !== project.brief_version && (
            <p className="error" role="alert">
              Бриф изменился. Закройте подтверждение и изучите актуальные предложения.
            </p>
          )}
          {project.state !== "open" && (
            <p className="owner-notice">Автор уже выбран. Откройте вкладку «Работа».</p>
          )}
          {award.error && (
            <p className="error" role="alert">
              {award.error}
            </p>
          )}
          <div className="owner-confirm-actions">
            <button
              className="owner-outline"
              disabled={award.pending}
              onClick={() => setConfirmation(null)}
            >
              Отмена
            </button>
            <button
              className="project-primary"
              disabled={
                award.pending ||
                confirmation.version !== project.brief_version ||
                project.state !== "open"
              }
              onClick={() => {
                void choose();
              }}
            >
              {award.pending ? "Фиксируем условия…" : "Начать работу"}
              <ArrowRight size={17} />
            </button>
          </div>
        </Modal>
      )}
      {editing && (
        <ProjectForm
          project={project}
          onClose={() => setEditing(false)}
          onSaved={() => {
            void refresh();
          }}
        />
      )}
    </div>
  );
}
