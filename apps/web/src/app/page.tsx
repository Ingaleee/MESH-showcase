"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import {
  ArrowDown,
  ArrowRight,
  Check,
  FileText,
  Package,
  Search,
  SlidersHorizontal,
  UserRound,
  Users,
  X,
} from "lucide-react";
import { api, type Profile, type Project } from "@/lib/api";
import { allDisciplines, disciplines, imagePath } from "@/lib/home-content";
import { CreateProjectButton } from "@/components/create-project-button";
import { Modal } from "@/components/modal";
import { useSession } from "@/components/session-provider";
import { HomeHero } from "@/components/home/hero";
import { HomeProjectCard } from "@/components/home/project-card";
import { HomeCreatorCard } from "@/components/home/creator-card";

type Feed = { data: Project[]; next_cursor: string | null };
const budgetRanges = [
  { label: "Любой бюджет", min: 0, max: Infinity },
  { label: "До 50 000 ₽", min: 0, max: 5000000 },
  { label: "50 000 — 100 000 ₽", min: 5000000, max: 10000000 },
  { label: "От 100 000 ₽", min: 10000000, max: Infinity },
];
const steps = [
  { title: "Опубликуйте бриф", text: "Расскажите о задаче, бюджете и сроках.", icon: FileText },
  {
    title: "Получите предложения",
    text: "Авторы поделятся подходом, ценой и сроком.",
    icon: Users,
  },
  {
    title: "Выберите автора",
    text: "Найдите человека, который понимает вашу идею.",
    icon: UserRound,
  },
  {
    title: "Получите результат",
    text: "Работа и её версии сохраняются в одном месте.",
    icon: Package,
  },
  { title: "Примите работу", text: "Подтвердите результат и завершите расчёты.", icon: Check },
];
const savedKey = "mesh:saved-projects:v1";

export default function ProjectsPage() {
  const { account } = useSession();
  const [feed, setFeed] = useState<Feed>({ data: [], next_cursor: null });
  const [heroProjects, setHeroProjects] = useState<Project[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [profilesError, setProfilesError] = useState("");
  const [category, setCategory] = useState("Все проекты");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [budget, setBudget] = useState(0);
  const [filters, setFilters] = useState(false);
  const [saved, setSaved] = useState<string[]>([]);
  const [onlySaved, setOnlySaved] = useState(false);
  const [storageError, setStorageError] = useState("");
  const [limit, setLimit] = useState(4);
  const [expanded, setExpanded] = useState(false);
  const searchInput = useRef<HTMLInputElement>(null);
  const currentQuery = useRef(0);

  useEffect(() => {
    try {
      const value: unknown = JSON.parse(localStorage.getItem(savedKey) ?? "[]");
      if (Array.isArray(value))
        setSaved(value.filter((item): item is string => typeof item === "string"));
    } catch {
      setStorageError("Не удалось прочитать сохранённые проекты в этом браузере.");
    }
    let active = true;
    api<{ data: Profile[] }>("/creators")
      .then((result) => {
        if (active) setProfiles(result.data);
      })
      .catch((failure: Error) => {
        if (active) setProfilesError(failure.message);
      });
    api<Feed>("/projects")
      .then((result) => {
        if (active) setHeroProjects(result.data);
      })
      .catch(() => {});
    function focusSearch(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        searchInput.current?.scrollIntoView({ block: "center" });
        searchInput.current?.focus({ preventScroll: true });
      }
    }
    window.addEventListener("keydown", focusSearch);
    return () => {
      active = false;
      window.removeEventListener("keydown", focusSearch);
    };
  }, []);

  useEffect(() => {
    const version = ++currentQuery.current;
    setLoading(true);
    setLimit(4);
    const timer = setTimeout(() => {
      const query = new URLSearchParams({
        q: search,
        ...(category !== "Все проекты" ? { category } : {}),
      });
      api<Feed>(`/projects?${query}`)
        .then((result) => {
          if (version === currentQuery.current) {
            setFeed(result);
            setError("");
          }
        })
        .catch((failure: Error) => {
          if (version === currentQuery.current) setError(failure.message);
        })
        .finally(() => {
          if (version === currentQuery.current) setLoading(false);
        });
    }, 200);
    return () => {
      clearTimeout(timer);
      if (currentQuery.current === version) currentQuery.current += 1;
    };
  }, [search, category, account]);

  const range = budgetRanges[budget];
  const projects = feed.data.filter(
    (project) =>
      (!onlySaved || saved.includes(project.id)) &&
      (budget === 0 ||
        (project.currency === "RUB" &&
          project.budget_minor >= range.min &&
          project.budget_minor <= range.max)),
  );
  const showingAll = !search && category === "Все проекты" && budget === 0 && !onlySaved;
  const featured = showingAll
    ? ["Дизайн", "Разработка", "Видео", "Маркетинг", "Тексты"]
        .map((name) => projects.find((project) => project.category === name))
        .filter((project): project is Project => Boolean(project))
    : [];
  const orderedProjects = [
    ...featured,
    ...projects.filter((project) => !featured.includes(project)),
  ];

  function toggleSaved(id: string) {
    const next = saved.includes(id) ? saved.filter((item) => item !== id) : [...saved, id];
    setSaved(next);
    try {
      localStorage.setItem(savedKey, JSON.stringify(next));
      setStorageError("");
    } catch {
      setStorageError(
        "Проект сохранён до закрытия страницы. Браузер не разрешает запись в хранилище.",
      );
    }
  }

  const reset = useCallback(() => {
    setCategory("Все проекты");
    setSearch("");
    setBudget(0);
    setOnlySaved(false);
    setExpanded(false);
  }, []);

  async function more() {
    if (!expanded && limit < projects.length) {
      setLimit((value) => value + 4);
      return;
    }
    if (!feed.next_cursor) return;
    const version = currentQuery.current;
    setLoading(true);
    try {
      const query = new URLSearchParams({
        q: search,
        cursor: feed.next_cursor,
        ...(category !== "Все проекты" ? { category } : {}),
      });
      const next = await api<Feed>(`/projects?${query}`);
      if (version === currentQuery.current) {
        setFeed((current) => ({
          data: [...current.data, ...next.data],
          next_cursor: next.next_cursor,
        }));
        setLimit((value) => value + 4);
      }
    } catch (failure) {
      if (version === currentQuery.current) setError((failure as Error).message);
    } finally {
      if (version === currentQuery.current) setLoading(false);
    }
  }

  return (
    <div className="home-page">
      <HomeHero projects={heroProjects} />

      <div className="home-search-bar" id="discover">
        <label className="home-search-field">
          <Search size={19} />
          <input
            id="project-search"
            ref={searchInput}
            aria-label="Поиск проектов"
            placeholder="Какой проект вы ищете?"
            value={search}
            onChange={(event) => {
              setSearch(event.target.value);
              setExpanded(false);
            }}
          />
          {search && (
            <button aria-label="Очистить поиск" onClick={() => setSearch("")}>
              <X size={15} />
            </button>
          )}
        </label>
        <div className="home-category-tabs" aria-label="Направление проекта">
          {[allDisciplines, ...disciplines].map(({ name, icon: Icon }) => (
            <button
              key={name}
              className={category === name ? "selected" : ""}
              aria-pressed={category === name}
              onClick={() => {
                setCategory(name);
                setExpanded(false);
              }}
            >
              <Icon size={17} />
              {name === "Все проекты" ? "Все категории" : name}
            </button>
          ))}
        </div>
        <button
          className={`home-filter-button ${budget || onlySaved ? "active" : ""}`}
          onClick={() => setFilters(true)}
        >
          <SlidersHorizontal size={17} />
          Фильтры{(budget !== 0 || onlySaved) && <i />}
        </button>
      </div>

      <section
        className="home-section home-disciplines"
        id="categories"
        aria-labelledby="categories-title"
      >
        <div className="home-section-heading">
          <h2 id="categories-title">Найдите своё направление</h2>
          <p>
            От первого слова до готового продукта.
            <br />
            Люди и идеи, которые подходят друг другу.
          </p>
          <a href="#discover" className="home-section-link" onClick={reset}>
            Все категории <ArrowRight size={17} />
          </a>
        </div>
        <div className="home-discipline-grid">
          {disciplines.map((discipline) => (
            <button
              key={discipline.name}
              className={`home-discipline-card ${discipline.dark ? "dark" : ""} ${category === discipline.name ? "active" : ""}`}
              aria-label={`Проекты в направлении ${discipline.name}`}
              onClick={() => {
                setCategory(discipline.name);
                setExpanded(false);
                document.getElementById("projects")?.scrollIntoView({ block: "start" });
              }}
            >
              <Image
                src={imagePath(discipline.image)}
                alt=""
                fill
                sizes="(max-width: 700px) 40vw, 240px"
              />
              <div>
                <h3>{discipline.name}</h3>
                <p>{discipline.description}</p>
              </div>
              <span className="round-arrow">
                <ArrowRight size={17} />
              </span>
            </button>
          ))}
        </div>
      </section>

      <section
        className="home-section home-projects"
        id="projects"
        aria-labelledby="projects-title"
      >
        <div className="home-section-heading">
          <h2 id="projects-title">{onlySaved ? "Сохранённые проекты" : "Актуальные проекты"}</h2>
          <span className="home-project-count" role="status">
            {loading ? "Находим проекты…" : `${projects.length} в подборке`}
          </span>
          <button
            className="home-section-link"
            onClick={() => {
              reset();
              setExpanded(true);
            }}
            disabled={loading}
          >
            Все проекты <ArrowRight size={17} />
          </button>
        </div>
        {!showingAll && (
          <div className="home-active-filters">
            <span>
              {category === "Все проекты" ? "Все направления" : category}
              {budget !== 0 ? ` · ${range.label}` : ""}
              {onlySaved ? " · Сохранённые" : ""}
              {search ? ` · «${search}»` : ""}
            </span>
            <button onClick={reset}>
              Сбросить <X size={13} />
            </button>
          </div>
        )}
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        {storageError && (
          <p className="home-storage-note" role="status">
            {storageError}
          </p>
        )}
        <div className="home-project-grid" aria-busy={loading}>
          {orderedProjects.slice(0, expanded ? undefined : limit).map((project, index) => (
            <HomeProjectCard
              key={project.id}
              project={project}
              index={index}
              saved={saved.includes(project.id)}
              onSave={() => toggleSaved(project.id)}
            />
          ))}
        </div>
        {!loading && projects.length === 0 && (
          <div className="home-empty-state">
            <Search size={28} />
            <h3>{onlySaved ? "Здесь будут ваши находки" : "Пока нет подходящих проектов"}</h3>
            <p>
              {onlySaved
                ? "Нажмите на закладку в карточке, чтобы сохранить проект."
                : "Попробуйте другой запрос, бюджет или направление."}
            </p>
            <button className="mesh-button mesh-button-light" onClick={reset}>
              Показать все проекты <ArrowRight size={16} />
            </button>
          </div>
        )}
        {((!expanded && limit < projects.length) || feed.next_cursor) && (
          <button
            className="home-load-more"
            disabled={loading}
            onClick={() => {
              void more();
            }}
          >
            Ещё проекты <ArrowDown size={16} />
          </button>
        )}
      </section>

      <section className="home-section" aria-labelledby="creators-title">
        <div className="home-section-heading">
          <h2 id="creators-title">Люди, которые создают</h2>
          <Link href="/creators" className="home-section-link">
            Все авторы <ArrowRight size={17} />
          </Link>
        </div>
        {profilesError && (
          <p className="error" role="alert">
            {profilesError}
          </p>
        )}
        <div className="home-creators-grid">
          {profiles.slice(0, 4).map((profile, index) => (
            <HomeCreatorCard key={profile.id} profile={profile} index={index} />
          ))}
        </div>
        {!profilesError && profiles.length === 0 && (
          <p className="home-storage-note">Знакомимся с авторами…</p>
        )}
      </section>

      <section className="home-section home-how" id="how-it-works" aria-labelledby="how-title">
        <div className="home-section-heading">
          <h2 id="how-title">Как это работает</h2>
          <p>От идеи до результата — в нескольких простых шагах.</p>
        </div>
        <ol className="home-steps">
          {steps.map(({ title, text, icon: Icon }, index) => (
            <li key={title}>
              <span className="step-number">{index + 1}</span>
              <span className="step-icon">
                <Icon size={24} strokeWidth={1.5} />
              </span>
              <div>
                <h3>{title}</h3>
                <p>{text}</p>
              </div>
              {index < steps.length - 1 && (
                <ArrowRight className="step-arrow" size={20} aria-hidden="true" />
              )}
            </li>
          ))}
        </ol>
      </section>

      <section className="home-final-cta" aria-labelledby="cta-title">
        <Image src={imagePath("creative-horizon")} alt="" fill sizes="100vw" quality={85} />
        <div className="home-cta-content">
          <span className="home-eyebrow">СОЗДАВАЙТЕ ВМЕСТЕ С НЕЗАВИСИМЫМИ АВТОРАМИ</span>
          <h2 id="cta-title">
            Ваши идеи заслуживают
            <br />
            <em>правильных людей.</em>
          </h2>
          <p>
            Первый шаг — рассказать о своей идее.
            <br />
            Дальше найдём тех, кто поможет ей случиться.
          </p>
          <CreateProjectButton
            className="mesh-button mesh-button-white"
            ariaLabel="Создать проект и найти автора"
          />
          <div className="home-cta-facts">
            <span>
              <strong>5</strong>творческих направлений
            </span>
            <span>
              <strong>Один бриф</strong>чтобы начать
            </span>
            <span>
              <strong>Вместе</strong>от идеи до результата
            </span>
          </div>
        </div>
        <span className="home-cta-note" aria-hidden="true">
          БОЛЬШЕ
          <br />
          ВОЗМОЖНОСТЕЙ
          <br />
          ВМЕСТЕ
        </span>
      </section>

      {filters && (
        <Modal title="Найдите подходящий проект" onClose={() => setFilters(false)}>
          <fieldset className="home-budget-options">
            <legend>Бюджет проекта в рублях</legend>
            {budgetRanges.map((item, index) => (
              <label key={item.label}>
                <input
                  type="radio"
                  name="budget-range"
                  checked={budget === index}
                  onChange={() => setBudget(index)}
                />
                <span>{item.label}</span>
              </label>
            ))}
          </fieldset>
          <label className="home-saved-option">
            <input
              type="checkbox"
              checked={onlySaved}
              onChange={(event) => setOnlySaved(event.target.checked)}
            />
            Только сохранённые проекты <span>{saved.length}</span>
          </label>
          <p className="home-filter-note">Закладки сохраняются в этом браузере.</p>
          <button
            className="mesh-button mesh-button-dark full-width"
            onClick={() => setFilters(false)}
          >
            Показать проекты <ArrowRight size={18} />
          </button>
        </Modal>
      )}
    </div>
  );
}
