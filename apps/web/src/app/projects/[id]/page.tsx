"use client";

import { use, useCallback, useEffect, useRef, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { ArrowRight, ArrowUpRight, Check, ChevronRight, FileText, Layers3 } from "lucide-react";
import { api, formatMoney, type Project, type ProjectDetail } from "@/lib/api";
import { projectArtwork } from "@/lib/project-content";
import { useSession } from "@/components/session-provider";
import { BriefContent } from "@/components/projects/brief-content";
import { ProjectHero } from "@/components/projects/project-hero";
import { OwnerProject } from "@/components/projects/owner-project";
import { ProposalBox } from "@/components/projects/proposal-box";
import { ProposalComposer } from "@/components/projects/proposal-composer";
import { exampleSize, exampleState } from "@/components/projects/proposal-example-input";

const bookmarkKey = "mesh:saved-projects:v1";

export default function ProjectPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const search = useSearchParams();
  const { account } = useSession();
  const actor = account?.id ?? "guest";
  const [loaded, setLoaded] = useState<{ data: ProjectDetail; actor: string } | null>(null);
  const [error, setError] = useState<{ message: string; actor: string } | null>(null);
  const [saved, setSaved] = useState(false);
  const [saveFeedback, setSaveFeedback] = useState("");
  const [relatedState, setRelated] = useState<{ scope: string; items: Project[] }>({
    scope: "",
    items: [],
  });
  const sequence = useRef(0);
  const pageElement = useRef<HTMLDivElement>(null);
  const refresh = useCallback(async () => {
    const request = ++sequence.current;
    try {
      const data = await api<ProjectDetail>(`/projects/${id}`);
      if (request === sequence.current) {
        setLoaded({ data, actor });
        setError(null);
      }
    } catch (failure) {
      if (request === sequence.current)
        setError({
          message: failure instanceof Error ? failure.message : "Не удалось загрузить проект.",
          actor,
        });
    }
  }, [id, actor]);
  useEffect(() => {
    void refresh();
    return () => {
      sequence.current++;
    };
  }, [refresh]);
  useEffect(() => {
    const read = () => {
      try {
        const value: unknown = JSON.parse(localStorage.getItem(bookmarkKey) ?? "[]");
        setSaved(Array.isArray(value) && value.includes(id));
      } catch {
        setSaved(false);
      }
    };
    read();
    window.addEventListener("storage", read);
    return () => window.removeEventListener("storage", read);
  }, [id]);
  const detail = loaded?.actor === actor && loaded.data.project.id === id ? loaded.data : null;
  const project = detail?.project;
  const composing =
    search.get("proposal") === "new" && !!account && project?.client.id !== account.id;
  function setComposing(value: boolean) {
    const query = new URLSearchParams(search.toString());
    if (value) query.set("proposal", "new");
    else query.delete("proposal");
    window.history.pushState(null, "", `/projects/${id}${query.size ? `?${query}` : ""}`);
    if (value) window.scrollTo({ top: 0, behavior: "instant" });
  }
  useEffect(() => {
    const root = pageElement.current;
    const card = root?.querySelector<HTMLElement>(".project-sticky");
    if (!root || !card) return;
    const measure = () => {
      const height = card.getBoundingClientRect().height;
      root.style.setProperty("--project-card-height", `${Math.ceil(height)}px`);
      card.classList.toggle("is-tall", height > window.innerHeight - 40);
    };
    const observer = new ResizeObserver(measure);
    observer.observe(card);
    window.addEventListener("resize", measure);
    measure();
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", measure);
    };
  }, [detail, error?.message, composing]);
  const relatedScope = `${actor}:${id}:${project?.category ?? ""}`;
  const related = relatedState.scope === relatedScope ? relatedState.items : [];
  useEffect(() => {
    if (!project) return;
    let active = true;
    void api<{ data: Project[] }>(`/projects?category=${encodeURIComponent(project.category)}`)
      .then((result) => {
        if (active)
          setRelated({
            scope: relatedScope,
            items: result.data.filter((item) => item.id !== project.id).slice(0, 2),
          });
      })
      .catch(() => {
        if (active) setRelated({ scope: relatedScope, items: [] });
      });
    return () => {
      active = false;
    };
  }, [relatedScope]);
  function toggleSave() {
    try {
      const value: unknown = JSON.parse(localStorage.getItem(bookmarkKey) ?? "[]");
      const ids = Array.isArray(value)
        ? value.filter((item): item is string => typeof item === "string")
        : [];
      const next = ids.includes(id) ? ids.filter((item) => item !== id) : [...ids, id];
      localStorage.setItem(bookmarkKey, JSON.stringify(next));
      setSaved(next.includes(id));
      setSaveFeedback(
        next.includes(id) ? "Проект сохранён в этом браузере" : "Проект убран из сохранённых",
      );
    } catch {
      setSaveFeedback("Браузер не разрешил сохранить проект.");
    }
  }
  if (error?.actor === actor)
    return (
      <div className="project-page project-loading">
        <p className="error" role="alert">
          {error.message}
        </p>
        <button
          className="button"
          onClick={() => {
            void refresh();
          }}
        >
          Попробовать ещё раз
        </button>
        <Link href="/#projects">Вернуться к проектам</Link>
      </div>
    );
  if (!detail || !project)
    return (
      <div className="project-page project-loading" aria-busy="true">
        <Layers3 size={30} />
        <h1>Загружаем бриф…</h1>
        <p>У каждой хорошей идеи есть начало.</p>
      </div>
    );
  const owner = project.client.id === account?.id;
  if (owner) return <OwnerProject key={`${id}-${actor}`} detail={detail} refresh={refresh} />;
  return (
    <div className={`project-page ${composing ? "is-composing" : ""}`} ref={pageElement}>
      <nav className="project-breadcrumbs" aria-label="Хлебные крошки">
        <Link href="/#projects">Проекты</Link>
        <ChevronRight size={13} />
        <Link href="/#categories">{project.category}</Link>
        <ChevronRight size={13} />
        <span>{project.title}</span>
      </nav>
      <ProjectHero project={project} proposalCount={detail.proposal_count} composing={composing} />
      {composing && account && (
        <ProposalComposer
          key={`${id}-${actor}`}
          project={project}
          account={account}
          proposals={detail.proposals}
          refresh={refresh}
          onClose={() => setComposing(false)}
        />
      )}
      <nav className="project-section-nav" aria-label="Разделы брифа">
        {composing && (
          <a className="proposal-mobile-anchor" href="#project-proposal">
            Ваше предложение
          </a>
        )}
        <a href="#project-about">О проекте</a>
        <a href="#project-requirements">Требования</a>
        <a href="#project-inspiration">Вдохновение</a>
        <a href="#project-materials">Материалы</a>
        <a href="#project-history">История</a>
        {account && (
          <a href="#project-offers">
            {owner ? "Предложения" : "Ваши предложения"}
            <span>{detail.proposals.length}</span>
          </a>
        )}
      </nav>
      <div className="project-body-grid">
        <article className="project-brief">
          <BriefContent project={project} history={detail.brief_history} />
          {account && (
            <section id="project-offers" className="project-section">
              <div className="project-section-heading">
                <h2>Ваши предложения</h2>
                <span className="project-pill">{detail.proposals.length}</span>
              </div>
              {detail.proposals.length ? (
                <div className="project-offer-list">
                  {detail.proposals.map((proposal) => (
                    <article className="project-offer" key={proposal.id}>
                      <div className="project-offer-heading">
                        <span className="project-client-mark">
                          {proposal.creator.display_name[0]}
                        </span>
                        <div>
                          <h3>{proposal.creator.display_name}</h3>
                          <span className="project-caption">
                            {proposal.delivery_days} дней · к брифу v{proposal.brief_version}
                          </span>
                        </div>
                        <strong>{formatMoney(proposal.price_minor, project.currency)}</strong>
                      </div>
                      <p className="project-prose">{proposal.message}</p>
                      {proposal.example && (
                        <div className="project-submitted-example">
                          <FileText size={20} />
                          <div>
                            <strong>{proposal.example.filename}</strong>
                            <span>
                              {exampleSize(proposal.example.byte_size)} ·{" "}
                              {exampleState(proposal.example.state)}
                            </span>
                          </div>
                          {proposal.example.state === "available" && (
                            <a
                              href={`/api/v1/projects/${id}/proposal_examples/${proposal.example.id}/download`}
                            >
                              Скачать <ArrowRight size={15} />
                            </a>
                          )}
                        </div>
                      )}
                    </article>
                  ))}
                </div>
              ) : (
                <div className="project-material-empty">
                  <ArrowUpRight size={25} />
                  <div>
                    <strong>Расскажите, как вы решите задачу</strong>
                    <p>Ваши предложения будут здесь. Другие авторы не увидят ваши условия.</p>
                  </div>
                </div>
              )}
            </section>
          )}
        </article>
        <aside className="project-side" aria-label="Условия проекта и заказчик">
          {!composing && (
            <div className="project-sticky">
              <ProposalBox
                key={`${id}-${actor}`}
                project={project}
                proposals={detail.proposals}
                saved={saved}
                onSave={toggleSave}
                onCompose={() => setComposing(true)}
              />
              <span className="project-save-feedback" role="status">
                {saveFeedback}
              </span>
            </div>
          )}
          <div className="project-how-to">
            <div>
              <strong>От идеи — к сотрудничеству</strong>
              <ol>
                <li>Изучите бриф и материалы</li>
                <li>Предложите цену, срок и подход</li>
                <li>Обсудите решение с заказчиком</li>
              </ol>
            </div>
            <Layers3 size={64} strokeWidth={0.8} />
          </div>
          {project.skills.length > 0 && (
            <section className="project-side-section">
              <h2>Навыки и экспертиза</h2>
              <div className="project-skills">
                {project.skills.map((skill, index) => (
                  <Link key={index} href={`/creators?q=${encodeURIComponent(skill)}`}>
                    {skill}
                  </Link>
                ))}
              </div>
            </section>
          )}
          <section id="project-client" className="project-side-section project-client-card">
            <h2>О заказчике</h2>
            <div className="project-hero-client">
              <span className="project-client-mark">{project.client.display_name[0]}</span>
              <div>
                <strong>{project.client.display_name}</strong>
                <span>Заказчик на MESH</span>
              </div>
            </div>
            <p>
              Создаёт этот проект и выбирает автора. Опишите свой подход — это поможет начать
              предметный разговор.
            </p>
            <span className="project-client-note">
              <Check size={17} />
              Условия и изменения фиксируются в брифе.
            </span>
          </section>
          {related.length > 0 && (
            <section className="project-side-section">
              <div className="project-section-heading">
                <h2>Похожие проекты</h2>
                <Link href="/#projects" aria-label="Все проекты">
                  <ArrowRight size={19} />
                </Link>
              </div>
              <div className="project-related">
                {related.map((item) => (
                  <Link key={item.id} href={`/projects/${item.id}`}>
                    <div>
                      <Image src={projectArtwork(item)} alt="" fill sizes="220px" />
                    </div>
                    <h3>{item.title}</h3>
                    <span className="project-pill">{item.category}</span>
                    <strong>{formatMoney(item.budget_minor, item.currency)}</strong>
                  </Link>
                ))}
              </div>
            </section>
          )}
        </aside>
      </div>
      <div className="project-closing">
        <span>ХОРОШИЕ ИДЕИ ОБРЕТАЮТ ФОРМУ</span>
        <h2>
          Всё начинается
          <br />с <em>правильных людей.</em>
        </h2>
        <Link href="/creators">
          Найти автора <ArrowRight size={18} />
        </Link>
      </div>
    </div>
  );
}
