"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import {
  ArrowLeft,
  ArrowRight,
  Bookmark,
  Check,
  CheckCheck,
  Feather,
  LockKeyhole,
} from "lucide-react";
import {
  api,
  ApiError,
  formatMoney,
  type Account,
  type Profile,
  type Project,
  type Proposal,
} from "@/lib/api";
import { briefDate } from "@/lib/project-content";
import { useCommand } from "@/lib/use-command";
import { useProposalDraft } from "./use-proposal-draft";
import { ProposalExampleInput } from "./proposal-example-input";

function minorAmount(value: string, scale: number) {
  if (!/^\d+(\.\d{1,2})?$/.test(value) || (scale === 1 && value.includes("."))) return null;
  const [whole, fraction = ""] = value.split(".");
  const minor = Number(whole) * scale + (scale === 1 ? 0 : Number(fraction.padEnd(2, "0")));
  return Number.isSafeInteger(minor) && minor > 0 && minor <= 100_000_000_000 ? minor : null;
}

export function ProposalComposer({
  project,
  account,
  proposals,
  refresh,
  onClose,
}: {
  project: Project;
  account: Account;
  proposals: Proposal[];
  refresh: () => Promise<void>;
  onClose: () => void;
}) {
  const { draft, setDraft, ready, feedback, save, clear } = useProposalDraft(project, account.id);
  const command = useCommand();
  const [agreed, setAgreed] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [profileState, setProfileState] = useState<"loading" | "found" | "missing" | "error">(
    "loading",
  );
  const current = proposals.find(
    (item) => item.creator.id === account.id && item.brief_version === project.brief_version,
  );
  const [sent, setSent] = useState(false);
  useEffect(() => {
    if (current) clear();
  }, [current, clear]);
  const outdated = draft.version !== project.brief_version;
  const scale = project.currency === "JPY" ? 1 : 100;
  const price = minorAmount(draft.price, scale);
  const days = /^\d+$/.test(draft.days) ? Number(draft.days) : 0;
  useEffect(() => {
    let active = true;
    void api<{ profile: Profile | null }>("/creators/mine")
      .then((result) => {
        if (!active) return;
        const own = result.profile;
        setProfile(own);
        setProfileState(own ? "found" : "missing");
      })
      .catch(() => {
        if (active) setProfileState("error");
      });
    return () => {
      active = false;
    };
  }, [account.id]);
  async function submit() {
    if (!ready || outdated || uploading || price === null || days < 1 || days > 365 || !agreed)
      return;
    try {
      await command.execute(`/projects/${project.id}/propose`, {
        proposal: {
          price_minor: price,
          delivery_days: days,
          message: draft.message.trim(),
          brief_version: draft.version,
          ...(draft.exampleId ? { example_id: draft.exampleId } : {}),
        },
      });
      clear();
      setSent(true);
      await refresh();
    } catch (failure) {
      if (
        failure instanceof ApiError &&
        (failure.code === "STALE_BRIEF" ||
          failure.code === "ALREADY_APPLIED" ||
          failure.code === "PROJECT_CLOSED" ||
          failure.code === "PROPOSALS_PAUSED")
      )
        await refresh();
      if (failure instanceof ApiError && failure.code === "PROFILE_REQUIRED")
        setProfileState("missing");
    }
  }
  return (
    <aside className="proposal-workspace" aria-label="Отправка предложения">
      <div className="proposal-composer project-terms" id="project-proposal">
        <div className="proposal-role">
          <span>
            <Feather size={17} />
            Вы предлагаете решение как автор
          </span>
          <span>v{draft.version}</span>
        </div>
        {current || sent ? (
          <div className="proposal-complete" role="status">
            <span>
              <CheckCheck size={34} />
            </span>
            <p className="proposal-eyebrow">НОВОЕ СОТРУДНИЧЕСТВО НАЧИНАЕТСЯ ЗДЕСЬ</p>
            <h2>Ваше предложение отправлено</h2>
            <p>Заказчик получил ваш подход и условия. Предложение видно только вам и заказчику.</p>
            <div className="proposal-complete-terms">
              <strong>{formatMoney(current?.price_minor ?? price ?? 0, project.currency)}</strong>
              <span>{current?.delivery_days ?? days} дней</span>
            </div>
            <button className="project-primary" onClick={onClose}>
              Вернуться к проекту <ArrowRight size={18} />
            </button>
          </div>
        ) : project.state !== "open" || !project.accepting_proposals ? (
          <div className="proposal-complete">
            <h2>
              {project.state !== "open"
                ? "Приём предложений завершён"
                : "Приём предложений на паузе"}
            </h2>
            <p>Ваш черновик сохранён в этом браузере.</p>
            <button className="project-primary" onClick={onClose}>
              Вернуться к проекту <ArrowRight size={18} />
            </button>
          </div>
        ) : (
          <>
            <div className="proposal-heading">
              <span className="proposal-eyebrow">ВАША ИДЕЯ. ВАШИ УСЛОВИЯ.</span>
              <h2>Ваше предложение</h2>
              <p>
                Расскажите, как вы решите задачу.
                <br />
                Хорошее сотрудничество начинается с ясности.
              </p>
            </div>
            <form
              className="project-proposal-form"
              onSubmit={(event) => {
                event.preventDefault();
                void submit();
              }}
            >
              {outdated && (
                <div className="project-version-warning" role="alert">
                  <strong>Бриф обновлён до v{project.brief_version}</strong>
                  <p>Изучите новые условия перед отправкой. Ваш черновик сохранён в форме.</p>
                  <button
                    type="button"
                    className="button compact"
                    onClick={() => {
                      setDraft((value) => ({ ...value, version: project.brief_version }));
                      setAgreed(false);
                      command.clearError();
                    }}
                  >
                    Я изучил новую версию
                  </button>
                </div>
              )}
              <div className="proposal-input-row">
                <label>
                  Ваша цена, {project.currency === "RUB" ? "₽" : project.currency}
                  <div className="proposal-price-input">
                    <input
                      name="price"
                      aria-label={`Ваша цена, ${project.currency === "RUB" ? "₽" : project.currency}`}
                      type="number"
                      inputMode="decimal"
                      min={1 / scale}
                      max={100_000_000_000 / scale}
                      step={1 / scale}
                      required
                      value={draft.price}
                      disabled={!ready || command.pending}
                      onChange={(event) =>
                        setDraft((value) => ({ ...value, price: event.target.value }))
                      }
                    />
                    <span aria-hidden="true">
                      {project.currency === "RUB" ? "₽" : project.currency}
                    </span>
                  </div>
                </label>
                <label>
                  Срок, дней
                  <div className="proposal-days-input">
                    <input
                      name="days"
                      aria-label="Срок, дней"
                      type="number"
                      inputMode="numeric"
                      min={1}
                      max={365}
                      step={1}
                      required
                      value={draft.days}
                      disabled={!ready || command.pending}
                      onChange={(event) =>
                        setDraft((value) => ({ ...value, days: event.target.value }))
                      }
                    />
                    <span aria-hidden="true">дней</span>
                  </div>
                </label>
              </div>
              <label className="proposal-message-label">
                Сообщение заказчику
                <textarea
                  name="message"
                  aria-label="Ваш подход"
                  rows={7}
                  maxLength={5000}
                  required
                  value={draft.message}
                  disabled={!ready || command.pending}
                  placeholder="Что вас заинтересовало в проекте? Как вы подойдёте к задаче, что войдёт в стоимость и какой результат получите?"
                  onChange={(event) =>
                    setDraft((value) => ({ ...value, message: event.target.value }))
                  }
                />
              </label>
              <div className="proposal-message-meta">
                <span>Ваш подход важнее шаблонного отклика.</span>
                <span>{draft.message.length} / 5000</span>
              </div>
              <ProposalExampleInput
                projectId={project.id}
                exampleId={draft.exampleId}
                disabled={command.pending || !ready}
                onBusy={setUploading}
                onChange={(exampleId) => setDraft((value) => ({ ...value, exampleId }))}
              />
              <div className="proposal-summary" aria-label="Итог предложения">
                <h3>Коротко о предложении</h3>
                <dl>
                  <div>
                    <dt>Бюджет заказчика</dt>
                    <dd>{formatMoney(project.budget_minor, project.currency)}</dd>
                  </div>
                  <div>
                    <dt>Ваше предложение</dt>
                    <dd>
                      {price !== null ? formatMoney(price, project.currency) : "Укажите цену"}
                    </dd>
                  </div>
                  <div>
                    <dt>Срок выполнения</dt>
                    <dd>{days >= 1 && days <= 365 ? `${days} дней` : "От 1 до 365 дней"}</dd>
                  </div>
                </dl>
                <p>
                  {price !== null && price > project.budget_minor
                    ? "Цена выше бюджета. Объясните в сообщении, что входит в эту стоимость."
                    : "Срок выполнения начинается после согласования условий."}
                </p>
              </div>
              <label className="proposal-consent">
                <input
                  type="checkbox"
                  required
                  checked={agreed}
                  disabled={command.pending}
                  onChange={(event) => setAgreed(event.target.checked)}
                />
                <span>
                  Я изучил бриф v{draft.version} и подтверждаю цену, срок и состав моего
                  предложения.
                </span>
              </label>
              {profileState === "missing" && (
                <p className="proposal-profile-warning">
                  Для отправки нужен профиль автора.{" "}
                  <Link href="/creators">
                    Заполнить профиль <ArrowRight size={14} />
                  </Link>
                </p>
              )}
              {command.error && (
                <p className="error" role="alert">
                  {command.error}
                </p>
              )}
              <button
                className="project-primary proposal-submit"
                disabled={!ready || command.pending || outdated || uploading}
              >
                <span>{command.pending ? "Отправляем…" : "Отправить предложение"}</span>
                <ArrowRight size={18} />
              </button>
              <div className="proposal-secondary-actions">
                <button
                  type="button"
                  disabled={!ready || command.pending || uploading}
                  onClick={save}
                >
                  <Bookmark size={16} />
                  Сохранить черновик
                </button>
                <button
                  type="button"
                  disabled={command.pending || uploading}
                  onClick={() => {
                    save();
                    onClose();
                  }}
                >
                  <ArrowLeft size={15} />К брифу
                </button>
              </div>
              <span className="proposal-draft-status" role="status">
                <Check size={13} />
                {feedback || "Черновик сохраняется автоматически в этом браузере"}
              </span>
              <p className="proposal-privacy">
                <LockKeyhole size={13} />
                Предложение увидит только заказчик. Дедлайн проекта — {briefDate(project.deadline)}.
              </p>
            </form>
          </>
        )}
      </div>
      <section className="proposal-profile-card">
        <div className="proposal-profile-top">
          <h2>Ваш профиль автора</h2>
          <Link href={profile ? `/creators?profile=${profile.id}` : "/creators"}>
            Открыть <ArrowRight size={14} />
          </Link>
        </div>
        <div className="proposal-profile-person">
          <span className="project-client-mark">{account.display_name[0]}</span>
          <div>
            <strong>{account.display_name}</strong>
            <span>
              {profile?.headline ??
                (profileState === "loading"
                  ? "Загружаем профиль…"
                  : profileState === "error"
                    ? "Профиль временно недоступен"
                    : "Профиль ещё не заполнен")}
            </span>
          </div>
          <Feather size={24} />
        </div>
        {profile && (
          <div className="project-skills">
            {profile.skills.slice(0, 5).map((skill) => (
              <span key={skill}>{skill}</span>
            ))}
          </div>
        )}
        <p>Пишите от своего имени. Заказчик сможет познакомиться с вашим опытом.</p>
      </section>
    </aside>
  );
}
