"use client";

import Link from "next/link";
import { ArrowRight, Bookmark, SlidersHorizontal, Search } from "lucide-react";
import { formatMoney, type Project, type Proposal } from "@/lib/api";
import { ProposalAvatar, ProposalExampleView, proposalTime } from "./owner-proposal-parts";

export type ProposalSort = "newest" | "price" | "days";
export function OwnerProposalList({
  project,
  proposals,
  visible,
  query,
  setQuery,
  sort,
  setSort,
  versionFilter,
  setVersionFilter,
  savedOnly,
  setSavedOnly,
  shortlist,
  toggleSave,
  selectedId,
  open,
  compareIds,
  toggleCompare,
  compareFeedback,
  totalCount,
  currentCount,
  matchedCount,
  hasMore,
  loading,
  error,
  loadMore,
}: {
  project: Project;
  proposals: Proposal[];
  visible: Proposal[];
  query: string;
  setQuery: (value: string) => void;
  sort: ProposalSort;
  setSort: (value: ProposalSort) => void;
  versionFilter: string;
  setVersionFilter: (value: string) => void;
  savedOnly: boolean;
  setSavedOnly: (value: boolean) => void;
  shortlist: string[];
  toggleSave: (id: string) => void;
  selectedId: string | null;
  open: (id: string) => void;
  compareIds: string[];
  toggleCompare: (id: string) => void;
  compareFeedback: string;
  totalCount: number;
  currentCount: number;
  matchedCount: number;
  hasMore: boolean;
  loading: boolean;
  error: string;
  loadMore: () => void;
}) {
  return (
    <section className="owner-offers-section" aria-labelledby="owner-offers-title">
      <div className="owner-offers-heading">
        <div>
          <span className="owner-kicker">ЛЮДИ, КОТОРЫЕ ВИДЯТ ВАШУ ИДЕЮ</span>
          <h2 id="owner-offers-title">
            Предложения авторов <span>{totalCount}</span>
          </h2>
        </div>
        <p>
          {currentCount} к текущему брифу · v{project.brief_version}
        </p>
      </div>
      <div className="owner-control-bar">
        <label className="owner-search">
          <Search size={17} />
          <input
            aria-label="Поиск по предложениям"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Автор или подход…"
          />
        </label>
        <select
          aria-label="Сортировка предложений"
          value={sort}
          onChange={(event) => setSort(event.target.value as ProposalSort)}
        >
          <option value="newest">Сначала новые</option>
          <option value="price">По цене ↑</option>
          <option value="days">По сроку ↑</option>
        </select>
        <select
          aria-label="Версия предложений"
          value={versionFilter}
          onChange={(event) => setVersionFilter(event.target.value)}
        >
          <option value="all">Все версии</option>
          <option value="current">К брифу v{project.brief_version}</option>
          <option value="old">Предыдущие</option>
        </select>
        <button
          className={`owner-filter-save ${savedOnly ? "is-active" : ""}`}
          aria-label="Только избранные предложения"
          aria-pressed={savedOnly}
          onClick={() => setSavedOnly(!savedOnly)}
        >
          <Bookmark size={17} />
        </button>
      </div>
      <div className="owner-list-meta">
        <span>
          Показано {visible.length} из {matchedCount}
        </span>
        <span>
          <SlidersHorizontal size={13} />
          Отметьте до 3 для сравнения
        </span>
      </div>
      <span className="owner-feedback" role="status">
        {compareFeedback}
      </span>
      {visible.length ? (
        <div className="owner-proposal-list">
          {visible.map((proposal) => {
            const stale = proposal.brief_version !== project.brief_version;
            return (
              <article
                className={`owner-proposal-card ${selectedId === proposal.id ? "is-selected" : ""} ${stale ? "is-outdated" : ""}`}
                key={proposal.id}
              >
                <label className="owner-compare-check">
                  <input
                    type="checkbox"
                    aria-label={`Сравнить предложение ${proposal.creator.display_name}, v${proposal.brief_version}`}
                    checked={compareIds.includes(proposal.id)}
                    onChange={() => toggleCompare(proposal.id)}
                  />
                </label>
                <div className="owner-card-person">
                  <ProposalAvatar proposal={proposal} />
                  <div>
                    <h3>{proposal.creator.display_name}</h3>
                    <p>{proposal.profile?.headline ?? "Автор на MESH"}</p>
                    <time dateTime={proposal.created_at}>{proposalTime(proposal.created_at)}</time>
                    <span className={`owner-version-chip ${stale ? "is-outdated" : ""}`}>
                      {stale
                        ? `Предыдущий бриф · v${proposal.brief_version}`
                        : `К текущему брифу · v${proposal.brief_version}`}
                    </span>
                  </div>
                  {proposal.profile?.skills.length ? (
                    <div className="owner-skill-list">
                      {proposal.profile.skills.slice(0, 3).map((skill) => (
                        <span key={skill}>{skill}</span>
                      ))}
                    </div>
                  ) : null}
                </div>
                <div className="owner-card-approach">
                  <p>{proposal.message}</p>
                  <ProposalExampleView projectId={project.id} proposal={proposal} />
                </div>
                <div className="owner-card-conditions">
                  <strong>{formatMoney(proposal.price_minor, project.currency)}</strong>
                  <span>{proposal.delivery_days} дней</span>
                  <div className="owner-card-actions">
                    <button
                      className={selectedId === proposal.id ? "project-primary" : "owner-outline"}
                      onClick={() => open(proposal.id)}
                      aria-label={`Посмотреть предложение ${proposal.creator.display_name}, v${proposal.brief_version}`}
                    >
                      Посмотреть детали <ArrowRight size={15} />
                    </button>
                    <button
                      className="owner-bookmark"
                      aria-label={`Сохранить предложение ${proposal.creator.display_name}, v${proposal.brief_version}`}
                      aria-pressed={shortlist.includes(proposal.id)}
                      onClick={() => toggleSave(proposal.id)}
                    >
                      <Bookmark
                        size={17}
                        fill={shortlist.includes(proposal.id) ? "currentColor" : "none"}
                      />
                    </button>
                  </div>
                  {proposal.profile && (
                    <Link
                      className="owner-profile-link"
                      href={`/creators?profile=${proposal.profile.id}`}
                    >
                      Профиль автора <ArrowRight size={12} />
                    </Link>
                  )}
                </div>
              </article>
            );
          })}
        </div>
      ) : (
        <div className="owner-empty">
          <span>
            <Search size={28} />
          </span>
          <h3>
            {proposals.length
              ? "Под эти условия пока никто не подходит"
              : "Первое предложение ещё впереди"}
          </h3>
          <p>
            {proposals.length
              ? "Измените поиск или выберите все версии брифа."
              : "Авторы увидят ваш проект и предложат свой подход, стоимость и срок. Когда появится отклик, он будет здесь."}
          </p>
        </div>
      )}
      <p className="owner-illustration-note">
        Портреты демо-авторов — иллюстрации MESH. Примеры в откликах — файлы, приложенные авторами.
      </p>
      <div className="owner-pagination">
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        {loading && <p role="status">Загружаем предложения…</p>}
        {hasMore && (
          <button className="owner-outline" disabled={loading} onClick={loadMore}>
            Показать ещё предложения
          </button>
        )}
      </div>
    </section>
  );
}
