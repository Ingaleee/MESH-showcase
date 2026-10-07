"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import {
  ArrowRight,
  ArrowUpRight,
  Bookmark,
  ChevronDown,
  Handshake,
  LayoutGrid,
  Search,
  Sparkles,
  X,
} from "lucide-react";
import { api, type Profile } from "@/lib/api";
import { authorCount, creatorDirection, creatorIndex } from "@/lib/creator-content";
import { disciplines, imagePath } from "@/lib/home-content";
import { useSession } from "@/components/session-provider";
import { CreateProjectButton } from "@/components/create-project-button";
import { CreatorCard } from "@/components/creators/card";
import { CreatorProfileDialog } from "@/components/creators/profile-dialog";
import { CreatorProfileEditor } from "@/components/creators/profile-editor";
import { ProjectForm } from "@/components/project-form";
import { Modal } from "@/components/modal";
import "./creators.css";

const storageKey = "mesh:saved-creators:v1";
const categoryOptions = [{ name: "Все", icon: LayoutGrid }, ...disciplines];

export default function CreatorsPage() {
  const { account, loading: sessionLoading, openLogin } = useSession();
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [directory, setDirectory] = useState<Profile[]>([]);
  const [directoryReady, setDirectoryReady] = useState(false);
  const [directoryError, setDirectoryError] = useState("");
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("Все");
  const [budget, setBudget] = useState("any");
  const [sort, setSort] = useState("default");
  const [saved, setSaved] = useState<string[]>([]);
  const [onlySaved, setOnlySaved] = useState(false);
  const [storageError, setStorageError] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [edit, setEdit] = useState(false);
  const [createProject, setCreateProject] = useState(false);
  const [selectedId, setSelectedId] = useState("");
  const [revision, setRevision] = useState(0);
  const searchInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const syncProfile = () =>
      setSelectedId(new URLSearchParams(window.location.search).get("profile") ?? "");
    syncProfile();
    setSearch(new URLSearchParams(window.location.search).get("q") ?? "");
    window.addEventListener("popstate", syncProfile);
    try {
      const stored: unknown = JSON.parse(localStorage.getItem(storageKey) ?? "[]");
      if (Array.isArray(stored))
        setSaved(stored.filter((value): value is string => typeof value === "string"));
    } catch {
      setStorageError("Браузер не смог загрузить сохранённых авторов.");
    }
    const shortcut = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        searchInput.current?.scrollIntoView({ block: "center" });
        searchInput.current?.focus({ preventScroll: true });
      }
    };
    window.addEventListener("keydown", shortcut);
    return () => {
      window.removeEventListener("popstate", syncProfile);
      window.removeEventListener("keydown", shortcut);
    };
  }, []);

  useEffect(() => {
    let active = true;
    setDirectoryReady(false);
    setDirectoryError("");
    void api<{ data: Profile[] }>("/creators")
      .then((result) => {
        if (active) setDirectory(result.data);
      })
      .catch((failure: Error) => {
        if (active) setDirectoryError(failure.message);
      })
      .finally(() => {
        if (active) setDirectoryReady(true);
      });
    return () => {
      active = false;
    };
  }, [account?.id, revision]);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    const timer = setTimeout(
      () => {
        void api<{ data: Profile[] }>(`/creators?q=${encodeURIComponent(search.trim())}`)
          .then((result) => {
            if (active) setProfiles(result.data);
          })
          .catch((failure: Error) => {
            if (active) setError(failure.message);
          })
          .finally(() => {
            if (active) setLoading(false);
          });
      },
      search ? 200 : 0,
    );
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [search, revision]);

  function openProfile(id: string) {
    const url = new URL(window.location.href);
    url.searchParams.set("profile", id);
    window.history.pushState(window.history.state, "", `${url.pathname}${url.search}`);
    setSelectedId(id);
  }

  function closeProfile() {
    const url = new URL(window.location.href);
    url.searchParams.delete("profile");
    window.history.replaceState(window.history.state, "", `${url.pathname}${url.search}`);
    setSelectedId("");
  }

  function toggleSaved(id: string) {
    const next = saved.includes(id) ? saved.filter((value) => value !== id) : [...saved, id];
    try {
      localStorage.setItem(storageKey, JSON.stringify(next));
      setSaved(next);
      setStorageError("");
    } catch {
      setStorageError("Не удалось сохранить автора в этом браузере. Проверьте доступ к хранилищу.");
    }
  }

  function reset() {
    setSearch("");
    setCategory("Все");
    setBudget("any");
    setSort("default");
    setOnlySaved(false);
  }

  function editProfile() {
    if (account && directoryError) {
      setRevision((value) => value + 1);
      return;
    }
    if (account) setEdit(true);
    else openLogin();
  }

  const visible = profiles.filter((profile) => {
    if (category !== "Все" && creatorDirection(profile) !== category) return false;
    if (onlySaved && !saved.includes(profile.id)) return false;
    if (budget !== "any") {
      if (profile.currency !== "RUB") return false;
      if (budget === "50" && profile.rate_minor > 5000000) return false;
      if (budget === "100" && (profile.rate_minor < 5000000 || profile.rate_minor > 10000000))
        return false;
      if (budget === "high" && profile.rate_minor < 10000000) return false;
    }
    return true;
  });
  if (sort === "name")
    visible.sort((left, right) =>
      left.account.display_name.localeCompare(right.account.display_name, "ru"),
    );
  if (sort === "low" || sort === "high")
    visible.sort((left, right) => {
      if (left.currency !== right.currency) return left.currency.localeCompare(right.currency);
      return sort === "low"
        ? left.rate_minor - right.rate_minor
        : right.rate_minor - left.rate_minor;
    });

  const filtered = Boolean(search.trim() || category !== "Все" || budget !== "any" || onlySaved);
  const catalogLoading = loading || !directoryReady;
  const own = directory.find((profile) => profile.account_id === account?.id);
  const selected =
    directory.find((profile) => profile.id === selectedId) ??
    profiles.find((profile) => profile.id === selectedId);

  const projectTile = (
    <aside
      className="directory-project-tile"
      key="project-tile"
      aria-label="Найти автора для проекта"
    >
      <Image
        src={imagePath("creative-horizon")}
        alt=""
        fill
        sizes="(max-width: 700px) 90vw, 330px"
      />
      <div>
        <Handshake size={26} strokeWidth={1.5} />
        <span className="directory-tile-kicker">ИДЕИ СОЕДИНЯЮТ ЛЮДЕЙ</span>
        <h2>
          Есть идея?
          <br />
          Найдём тех,
          <br />
          кто её воплотит.
        </h2>
        <p>Расскажите о задаче. Авторы предложат свой подход, сроки и стоимость.</p>
        <CreateProjectButton
          className="mesh-button mesh-button-white"
          ariaLabel="Создать проект из каталога"
        />
      </div>
    </aside>
  );

  return (
    <div className="directory-page">
      <div className="directory-search-row">
        <div className="directory-search">
          <Search size={21} aria-hidden="true" />
          <input
            id="creator-search"
            ref={searchInput}
            aria-label="Поиск авторов"
            maxLength={100}
            placeholder="Искать по имени, навыкам или специализации…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
          {search ? (
            <button
              aria-label="Очистить поиск авторов"
              onClick={() => {
                setSearch("");
                searchInput.current?.focus();
              }}
            >
              <X size={17} />
            </button>
          ) : (
            <kbd aria-hidden="true">⌘ / Ctrl K</kbd>
          )}
        </div>
        <button
          className="directory-my-profile"
          disabled={sessionLoading || (Boolean(account) && !directoryReady)}
          onClick={editProfile}
        >
          Мой профиль <ArrowUpRight size={17} />
        </button>
      </div>

      <div className="directory-filter-bar" aria-label="Фильтры авторов">
        <div className="directory-categories" role="group" aria-label="Направление автора">
          {categoryOptions.map(({ name, icon: Icon }) => (
            <button
              key={name}
              className={category === name ? "selected" : ""}
              aria-pressed={category === name}
              onClick={() => setCategory(name)}
            >
              <Icon size={18} />
              {name}
            </button>
          ))}
        </div>
        <div className="directory-filter-controls">
          <label className="directory-select">
            <select
              aria-label="Бюджет за проект"
              value={budget}
              onChange={(event) => setBudget(event.target.value)}
            >
              <option value="any">Бюджет</option>
              <option value="50">До 50 000 ₽</option>
              <option value="100">50 000–100 000 ₽</option>
              <option value="high">От 100 000 ₽</option>
            </select>
            <ChevronDown size={14} aria-hidden="true" />
          </label>
          <label className="directory-select">
            <select
              aria-label="Сортировка авторов"
              value={sort}
              onChange={(event) => setSort(event.target.value)}
            >
              <option value="default">Сортировка</option>
              <option value="low">Стоимость ↑</option>
              <option value="high">Стоимость ↓</option>
              <option value="name">По имени</option>
            </select>
            <ChevronDown size={14} aria-hidden="true" />
          </label>
          <button
            className={`directory-saved-filter ${onlySaved ? "selected" : ""}`}
            aria-label={`Сохранённые авторы${saved.length ? ` (${saved.length})` : ""}`}
            aria-pressed={onlySaved}
            onClick={() => setOnlySaved(!onlySaved)}
          >
            <Bookmark size={17} />
            <span className="directory-saved-label">Сохранённые</span>
            {saved.length > 0 && <span className="directory-saved-count">{saved.length}</span>}
          </button>
        </div>
      </div>

      <section
        className="directory-catalog"
        aria-labelledby="directory-title"
        aria-busy={catalogLoading}
      >
        <div className="directory-heading">
          <div>
            <h1 id="directory-title">
              Найдите своего автора<span>.</span>
            </h1>
            <p>Разные таланты. Сильные идеи. Ваше следующее сотрудничество.</p>
          </div>
          <div className="directory-results">
            <span role="status">
              {catalogLoading
                ? "Ищем авторов…"
                : error
                  ? "Каталог недоступен"
                  : authorCount(visible.length)}
            </span>
            {filtered && (
              <button onClick={reset}>
                Сбросить фильтры <X size={14} />
              </button>
            )}
          </div>
        </div>
        {storageError && (
          <p className="directory-feedback" role="alert">
            {storageError}
          </p>
        )}
        {account && directoryError && !error && (
          <p className="directory-feedback" role="alert">
            Не удалось загрузить ваш профиль. Нажмите «Мой профиль», чтобы повторить запрос.
          </p>
        )}
        {error ? (
          <div className="directory-empty" role="alert">
            <Search size={30} />
            <h2>Не удалось загрузить авторов</h2>
            <p>{error}</p>
            <button
              className="mesh-button mesh-button-light"
              onClick={() => setRevision((value) => value + 1)}
            >
              Попробовать снова <ArrowRight size={17} />
            </button>
          </div>
        ) : (loading && profiles.length === 0) || (!directoryReady && directory.length === 0) ? (
          <div className="directory-grid" aria-hidden="true">
            {[0, 1, 2, 3].map((index) => (
              <div key={index} className="directory-skeleton">
                <span />
                <div />
                <div />
                <div />
              </div>
            ))}
          </div>
        ) : (
          <>
            <div className="directory-grid">
              {visible.flatMap((profile, position) => {
                const card = (
                  <CreatorCard
                    key={profile.id}
                    profile={profile}
                    index={creatorIndex(profile, directory)}
                    saved={saved.includes(profile.id)}
                    onSave={() => toggleSaved(profile.id)}
                    onOpen={() => openProfile(profile.id)}
                  />
                );
                return position === 2 && !filtered ? [card, projectTile] : [card];
              })}
              {!filtered && visible.length > 0 && visible.length < 3 && projectTile}
              {!filtered && visible.length > 0 && (
                <aside className="directory-join-tile">
                  <span className="directory-join-symbol">
                    <Sparkles size={27} />
                  </span>
                  <span className="directory-tile-kicker">ВАШ ТАЛАНТ — ЧЬЯ-ТО НОВАЯ ИДЕЯ</span>
                  <h2>
                    Создаёте
                    <br />
                    что-то классное?
                  </h2>
                  <p>
                    Расскажите о своём подходе, добавьте навыки и находите проекты, которые вам
                    близки.
                  </p>
                  <button
                    className="mesh-button mesh-button-light"
                    disabled={sessionLoading || (Boolean(account) && !directoryReady)}
                    onClick={editProfile}
                  >
                    {own ? "Редактировать профиль" : "Создать профиль"}
                    <ArrowUpRight size={18} />
                  </button>
                </aside>
              )}
            </div>
            {!catalogLoading && visible.length === 0 && (
              <div className="directory-empty">
                <span>
                  <Search size={28} />
                </span>
                <h2>{onlySaved ? "Здесь будут ваши находки" : "Пока нет подходящих авторов"}</h2>
                <p>
                  {onlySaved
                    ? "Сохраняйте понравившихся авторов с помощью закладки в карточке. Если уже сохранили — попробуйте снять остальные фильтры."
                    : "Попробуйте другое имя, навык, направление или бюджет."}
                </p>
                <button className="mesh-button mesh-button-light" onClick={reset}>
                  Показать всех авторов <ArrowRight size={17} />
                </button>
              </div>
            )}
          </>
        )}
        <p className="directory-demo-note directory-catalog-note">
          Знакомьтесь с подходом и навыками. Портреты и визуальные превью — иллюстрации демо-версии.
        </p>
      </section>

      <section className="directory-final-cta" aria-labelledby="directory-cta-title">
        <Image src={imagePath("creative-horizon")} alt="" fill sizes="100vw" quality={85} />
        <div className="directory-final-content">
          <span className="directory-tile-kicker">СОЗДАВАЙТЕ ВМЕСТЕ С НЕЗАВИСИМЫМИ АВТОРАМИ</span>
          <h2 id="directory-cta-title">
            Ваши идеи заслуживают
            <br />
            <em>правильных людей.</em>
          </h2>
          <p>
            Один понятный бриф — начало
            <br />
            вашего следующего большого дела.
          </p>
          <CreateProjectButton
            className="mesh-button mesh-button-white"
            ariaLabel="Создать проект и найти автора"
          />
        </div>
        <span className="directory-final-note">
          БОЛЬШИЕ
          <br />
          ВОЗМОЖНОСТИ
          <br />
          НАЧИНАЮТСЯ СО СВЯЗИ
        </span>
      </section>

      {selected && (
        <CreatorProfileDialog
          profile={selected}
          index={creatorIndex(selected, directory)}
          saved={saved.includes(selected.id)}
          onSave={() => toggleSaved(selected.id)}
          onClose={closeProfile}
          onCreateProject={() => {
            closeProfile();
            if (account) setCreateProject(true);
            else openLogin();
          }}
        />
      )}
      {selectedId && directoryReady && !loading && !selected && (
        <Modal title="Автор не найден" onClose={closeProfile}>
          <p className="muted">Профиль недоступен. Выберите другого автора в каталоге.</p>
          <button className="mesh-button mesh-button-dark" onClick={closeProfile}>
            Вернуться к авторам
          </button>
        </Modal>
      )}
      {edit && (
        <CreatorProfileEditor
          profile={own}
          onClose={() => setEdit(false)}
          onSaved={() => {
            setEdit(false);
            setRevision((value) => value + 1);
          }}
        />
      )}
      {createProject && <ProjectForm onClose={() => setCreateProject(false)} />}
    </div>
  );
}
