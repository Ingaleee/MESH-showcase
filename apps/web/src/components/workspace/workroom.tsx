"use client";

import Link from "next/link";
import { useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  BriefcaseBusiness,
  CalendarDays,
  Check,
  CheckCircle2,
  Download,
  FolderOpen,
  LockKeyhole,
  MessageCircle,
  MoreHorizontal,
  Send,
  ShieldCheck,
  Wallet,
} from "lucide-react";
import { formatMoney, type Engagement, type Submission } from "@/lib/api";
import { briefDate, projectArtwork } from "@/lib/project-content";
import { useCommand } from "@/lib/use-command";
import { Modal } from "@/components/modal";
import { FinancePanel } from "@/components/workspace/finance-panel";
import { VersionComposer } from "@/components/workspace/version-composer";
import { useWorkHistory } from "./use-work-history";
import { WorkFileLink } from "./work-files";
import {
  Progress,
  VersionCard,
  Terms,
  activity,
  Activity,
  FeedbackComposer,
  workTime as time,
} from "./workroom-parts";

const states: Record<string, string> = {
  agreed: "Условия согласованы",
  in_progress: "В работе",
  submitted: "На проверке",
  accepted: "Принято",
  cancelled: "Отменено",
};
const tabs = [
  { id: "work", title: "Работа", icon: BriefcaseBusiness },
  { id: "comments", title: "Комментарии", icon: MessageCircle },
  { id: "files", title: "Файлы", icon: FolderOpen },
  { id: "terms", title: "Условия", icon: ShieldCheck },
  { id: "events", title: "События", icon: CalendarDays },
  { id: "finance", title: "Расчёты", icon: Wallet },
] as const;
type Tab = (typeof tabs)[number]["id"];

export function Workroom({
  engagement: initialEngagement,
  actorId,
  refresh,
  items,
  select,
}: {
  engagement: Engagement;
  actorId: string;
  refresh: () => Promise<void>;
  items: Engagement[];
  select: (id: string) => void;
}) {
  const history = useWorkHistory(initialEngagement);
  const engagement = history.engagement;
  const [tab, setTab] = useState<Tab>("work");
  const [composer, setComposer] = useState(false);
  const [terms, setTerms] = useState(false);
  const [message, setMessage] = useState<{
    kind: "comment" | "changes_requested";
    submission: Submission | null;
  } | null>(null);
  const [accepting, setAccepting] = useState<Submission | null>(null);
  const [notice, setNotice] = useState("");
  const command = useCommand();
  const creator = actorId === engagement.creator_id;
  const latest = engagement.submissions[0];
  const writable = ["agreed", "in_progress", "submitted"].includes(engagement.state);
  const events = activity(engagement);
  const title = engagement.terms.title;
  const client = engagement.client;

  async function start() {
    try {
      await command.execute(`/engagements/${engagement.id}/start`, {});
      await refresh();
    } catch {}
  }
  async function accept() {
    if (!accepting || command.pending) return;
    try {
      await command.execute(`/engagements/${engagement.id}/accept`, {
        submission_id: accepting.id,
      });
      setAccepting(null);
      await refresh();
    } catch {}
  }
  async function downloadAll() {
    if (!latest?.files.length) return;
    setNotice("");
    try {
      const response = await fetch(
        `/api/v1/engagements/${engagement.id}/archive?submission_id=${latest.id}`,
        { credentials: "same-origin" },
      );
      if (!response.ok) {
        const failure = await response.json();
        throw new Error(
          failure.code === "ZIP_LIMIT"
            ? "В версии больше 50 МБ. Скачайте файлы отдельно."
            : failure.code === "FILE_QUARANTINED"
              ? "Дождитесь проверки всех файлов версии."
              : "Не удалось скачать архив.",
        );
      }
      const url = URL.createObjectURL(await response.blob());
      const link = document.createElement("a");
      link.href = url;
      link.download = `MESH-version-${latest.version}.zip`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (failure) {
      setNotice(failure instanceof Error ? failure.message : "Не удалось скачать архив.");
    }
  }

  return (
    <div className="workroom">
      <aside className="workroom-nav">
        <Link className="workroom-back" href="/#projects">
          <ArrowLeft size={16} />
          Все проекты
        </Link>
        <div className="workroom-project-cover">
          <img src={projectArtwork(engagement.terms)} alt="Визуальное направление проекта" />
        </div>
        <p className="workroom-project-title">{title}</p>
        <span className="workroom-small-client">
          <span className="workroom-initial">{client.display_name[0]}</span>
          {client.display_name}
        </span>
        <nav aria-label="Разделы проекта">
          {tabs.map(({ id, title: label, icon: Icon }) => (
            <button
              key={id}
              aria-pressed={tab === id}
              className={tab === id ? "is-active" : ""}
              onClick={() => setTab(id)}
            >
              <Icon size={19} />
              {label}
              {id === "comments" && engagement.feedback.length > 0 && (
                <span>{engagement.feedback.length}</span>
              )}
            </button>
          ))}
        </nav>
        <label className="workroom-project-switch">
          Мои проекты
          <select value={engagement.id} onChange={(event) => select(event.target.value)}>
            {items.map((item) => (
              <option key={item.id} value={item.id}>
                {item.terms.title}
              </option>
            ))}
          </select>
        </label>
        {items.length >= 40 && (
          <p className="workroom-help">Показаны последние 40 соглашений и открытый проект.</p>
        )}
        <div className="workroom-nav-note">
          <LockKeyhole size={17} />
          <span>Рабочие материалы видны только участникам проекта.</span>
        </div>
      </aside>
      <div className="workroom-center">
        <header className="workroom-heading">
          <div>
            <span className="workroom-eyebrow">МОЯ РАБОТА / {creator ? "АВТОР" : "ЗАКАЗЧИК"}</span>
            <h1>{title}</h1>
            <p>
              <span className="workroom-initial">{client.display_name[0]}</span>
              {client.display_name}
              <span>·</span>
              {engagement.creator.display_name}
            </p>
          </div>
          <div className="workroom-heading-actions">
            <span
              className={`workroom-project-status ${engagement.state === "accepted" ? "is-accepted" : ""}`}
            >
              <i />
              {states[engagement.state]}
            </span>
            <details className="workroom-menu">
              <summary aria-label="Действия проекта">
                <MoreHorizontal size={20} />
              </summary>
              <div>
                <Link href={`/projects/${engagement.project_id}`}>Открыть публичный бриф</Link>
                <button
                  onClick={() => {
                    void downloadAll();
                  }}
                  disabled={!latest?.files.length}
                >
                  Скачать файлы текущей версии
                </button>
                <button onClick={() => setTab("finance")}>Открыть спор / расчёты</button>
              </div>
            </details>
          </div>
        </header>
        <Progress state={engagement.state} />
        {(command.error || notice) && (
          <p role="alert" className="error">
            {command.error || notice}
          </p>
        )}
        {tab === "work" && (
          <>
            <div className="workroom-section-heading">
              <h2>Текущая версия</h2>
              <div>
                {latest?.files.length > 0 && (
                  <button className="button workroom-download" onClick={() => void downloadAll()}>
                    <Download size={15} />
                    Скачать все
                  </button>
                )}
                {creator && writable && (
                  <button className="button primary" onClick={() => setComposer(true)}>
                    Передать новую версию
                    <ArrowRight size={17} />
                  </button>
                )}
              </div>
            </div>
            {latest ? (
              <VersionCard
                engagement={engagement}
                submission={latest}
                onComment={() => setMessage({ kind: "comment", submission: latest })}
              />
            ) : (
              <section className="workroom-empty workroom-card">
                <span className="workroom-empty-icon">
                  <FolderOpen size={30} />
                </span>
                <h2>
                  {creator ? "Здесь появится ваша первая версия" : "Ждём первую версию от автора"}
                </h2>
                <p>
                  Условия согласованы. Передайте результат с файлами и поясните свои решения —
                  каждая версия останется в истории.
                </p>
                {creator && engagement.state === "agreed" && (
                  <button
                    className="button"
                    disabled={command.pending}
                    onClick={() => void start()}
                  >
                    Начать работу
                    <ArrowRight size={17} />
                  </button>
                )}
              </section>
            )}
            {!creator && latest && engagement.state === "submitted" && (
              <div className="workroom-review">
                <div>
                  <ShieldCheck size={20} />
                  <p>
                    <strong>
                      {latest.ready_for_acceptance
                        ? "Проверьте результат перед принятием"
                        : "Версия для обсуждения"}
                    </strong>
                    <span>
                      {latest.ready_for_acceptance
                        ? "Решение будет закреплено за этой версией."
                        : "Автор пока не отметил готовность к принятию."}
                    </span>
                  </p>
                </div>
                <button
                  className="button"
                  onClick={() => setMessage({ kind: "changes_requested", submission: latest })}
                >
                  Запросить изменения
                </button>
                {latest.ready_for_acceptance && (
                  <button
                    className="button primary"
                    onClick={() => {
                      command.clearError();
                      setAccepting(latest);
                    }}
                  >
                    Принять эту версию
                    <Check size={17} />
                  </button>
                )}
              </div>
            )}
            {engagement.state === "accepted" && (
              <p className="workroom-success" role="status">
                <CheckCircle2 size={19} />
                Результат принят заказчиком
              </p>
            )}
            <div className="workroom-section-heading history-heading">
              <h2>История версий</h2>
              {history.nextVersions && (
                <button
                  className="button"
                  disabled={history.loading}
                  onClick={() => void history.load("versions")}
                >
                  Показать предыдущие версии
                </button>
              )}
              <span>
                {engagement.submissions.length}{" "}
                {engagement.submissions.length === 1 ? "передача" : "передач"}
              </span>
            </div>
            <div className="workroom-history">
              {engagement.submissions.slice(1).map((submission) => (
                <VersionCard
                  key={submission.id}
                  engagement={engagement}
                  submission={submission}
                  compact
                  onComment={() => setMessage({ kind: "comment", submission })}
                />
              ))}
              {engagement.submissions.length < 2 && (
                <p className="workroom-help">
                  Предыдущие передачи появятся здесь. История сохраняется после новой версии.
                </p>
              )}
            </div>
          </>
        )}
        {tab === "files" && (
          <section>
            <div className="workroom-section-heading">
              <h2>Файлы проекта</h2>
              <span>По версиям результата</span>
            </div>
            {engagement.submissions.map((submission) => (
              <section key={submission.id} className="workroom-card workroom-files-section">
                <h3>
                  Версия {submission.version} · {submission.title || "Результат работы"}
                </h3>
                <div className="workroom-files">
                  {submission.files.map((file) => (
                    <WorkFileLink key={file.id} engagementId={engagement.id} file={file} />
                  ))}
                </div>
                {!submission.files.length && (
                  <p className="workroom-help">Передана текстовая версия без вложений.</p>
                )}
              </section>
            ))}
            {!engagement.submissions.length && (
              <p className="workroom-help">Пока нет переданных файлов.</p>
            )}
          </section>
        )}
        {history.error && (
          <p className="error" role="alert">
            {history.error}
          </p>
        )}
        {history.nextFeedback && (tab === "comments" || tab === "work") && (
          <button
            className="button"
            disabled={history.loading}
            onClick={() => void history.load("feedback")}
          >
            Показать предыдущие комментарии
          </button>
        )}
        {tab === "comments" && (
          <section className="workroom-card workroom-comments">
            <div className="workroom-section-heading">
              <h2>Комментарии к работе</h2>
              <button
                className="button primary"
                onClick={() => setMessage({ kind: "comment", submission: latest ?? null })}
              >
                Написать
                <Send size={16} />
              </button>
            </div>
            <p className="workroom-help">
              Обсуждение сохраняется вместе с версией, к которой относится.
            </p>
            {engagement.feedback.map((feedback) => (
              <div key={feedback.id} className="workroom-feedback">
                <div>
                  <strong>{feedback.actor.display_name}</strong>
                  <time dateTime={feedback.created_at}>{time(feedback.created_at)}</time>
                </div>
                <span className="workroom-feedback-context">
                  {feedback.submission_id
                    ? `Версия ${engagement.submissions.find((item) => item.id === feedback.submission_id)?.version ?? ""}`
                    : "Весь проект"}{" "}
                  · {feedback.kind === "changes_requested" ? "Запрос изменений" : "Комментарий"}
                </span>
                <p>{feedback.content}</p>
              </div>
            ))}
            {!engagement.feedback.length && (
              <p className="workroom-help">Начните обсуждение с заказчиком.</p>
            )}
          </section>
        )}
        {tab === "terms" && (
          <section className="workroom-card workroom-terms-full">
            <h2>Зафиксированные условия</h2>
            <p className="workroom-help">
              Сохранены в момент выбора автора. Бриф и новые передачи не меняют это соглашение.
            </p>
            <Terms engagement={engagement} />
          </section>
        )}
        {tab === "events" && (
          <section className="workroom-card workroom-events-full">
            <h2>События проекта</h2>
            <Activity events={events} />
          </section>
        )}
        {tab === "finance" && <FinancePanel engagement={engagement} actorId={actorId} />}
      </div>
      <aside className="workroom-right">
        <div className="workroom-sticky">
          <section className="workroom-card workroom-conditions">
            <h2>Условия проекта</h2>
            <dl>
              <div>
                <dt>Стоимость</dt>
                <dd>{formatMoney(engagement.terms.price_minor, engagement.terms.currency)}</dd>
              </div>
              <div>
                <dt>Срок работы</dt>
                <dd>{engagement.terms.delivery_days} дней</dd>
              </div>
              <div>
                <dt>Дедлайн брифа</dt>
                <dd>{briefDate(engagement.terms.deadline)}</dd>
              </div>
              <div>
                <dt>Предложение принято</dt>
                <dd className="is-light">{time(engagement.created_at)}</dd>
              </div>
            </dl>
            <button className="workroom-text-link" onClick={() => setTerms(true)}>
              Посмотреть зафиксированные условия
              <ArrowRight size={15} />
            </button>
          </section>
          <section className="workroom-card workroom-customer">
            <h2>{creator ? "Заказчик" : "Автор"}</h2>
            <div className="workroom-person">
              <span>{(creator ? client : engagement.creator).display_name[0]}</span>
              <div>
                <strong>{(creator ? client : engagement.creator).display_name}</strong>
                <p>Участник проекта на MESH</p>
              </div>
            </div>
            <button
              className="button workroom-wide"
              onClick={() => setMessage({ kind: "comment", submission: latest ?? null })}
            >
              Написать
              <MessageCircle size={16} />
            </button>
            <div className="workroom-trust-note">
              <ShieldCheck size={18} />
              <p>
                Условия зафиксированы.
                <br />
                Отзывы сохраняются по версиям.
              </p>
            </div>
            <Link className="workroom-text-link" href={`/projects/${engagement.project_id}`}>
              Открыть бриф
              <ArrowRight size={15} />
            </Link>
          </section>
          <section className="workroom-card workroom-activity">
            <div className="workroom-section-heading">
              <h2>Последняя активность</h2>
              <button className="workroom-text-link" onClick={() => setTab("events")}>
                Все
                <ArrowRight size={14} />
              </button>
            </div>
            <Activity events={events.slice(0, 4)} />
          </section>
        </div>
      </aside>
      {composer && (
        <VersionComposer
          engagement={engagement}
          actorId={actorId}
          onClose={() => setComposer(false)}
          refresh={refresh}
        />
      )}
      {terms && (
        <Modal
          title="Зафиксированные условия"
          className="workroom-terms-modal"
          onClose={() => setTerms(false)}
        >
          <p className="workroom-help">
            Соглашение от {time(engagement.created_at)} · бриф v{engagement.terms.brief_version}
          </p>
          <Terms engagement={engagement} />
        </Modal>
      )}
      {message && (
        <FeedbackComposer
          key={`${message.kind}:${message.submission?.id ?? "project"}`}
          engagement={engagement}
          kind={message.kind}
          submission={message.submission}
          onClose={() => setMessage(null)}
          refresh={refresh}
        />
      )}
      {accepting && (
        <Modal
          title={`Принять версию ${accepting.version}?`}
          onClose={() => {
            if (!command.pending) setAccepting(null);
          }}
        >
          <p>{accepting.title || "Результат работы"}</p>
          <p className="workroom-help">
            Приёмка закрепится за этой передачей. Если автор уже передал новую версию, MESH попросит
            сначала проверить её.
          </p>
          {command.error && (
            <p className="error" role="alert">
              {command.error}
            </p>
          )}
          <div className="button-row">
            <button
              className="button"
              disabled={command.pending}
              onClick={() => setAccepting(null)}
            >
              Отмена
            </button>
            <button
              className="button primary"
              disabled={command.pending}
              onClick={() => void accept()}
            >
              Подтвердить приёмку
              <Check size={17} />
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
