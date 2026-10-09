"use client";

import { useState } from "react";
import { Check, MessageCircle, Send } from "lucide-react";
import { formatMoney, type Engagement, type Submission } from "@/lib/api";
import { briefDate } from "@/lib/project-content";
import { useCommand } from "@/lib/use-command";
import { Modal } from "@/components/modal";
import { WorkFileLink, WorkImage } from "./work-files";

export function workTime(value: string) {
  return new Date(value).toLocaleString("ru-RU", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function Progress({ state }: { state: string }) {
  const current =
    state === "agreed"
      ? 0
      : state === "in_progress"
        ? 1
        : state === "submitted"
          ? 3
          : state === "accepted"
            ? 4
            : -1;
  return (
    <ol className="workroom-progress" aria-label="Этапы проекта">
      {["Бриф", "Работа", "Передача", "Проверка", "Принято"].map((step, index) => (
        <li
          key={step}
          className={`${index < current ? "is-complete" : ""} ${index === current ? "is-current" : ""}`}
          aria-current={index === current ? "step" : undefined}
        >
          <span>{index < current ? <Check size={12} /> : index + 1}</span>
          <strong>{step}</strong>
        </li>
      ))}
    </ol>
  );
}

function versionState(engagement: Engagement, submission: Submission) {
  if (engagement.accepted_submission_id === submission.id)
    return { text: "Принята", kind: "accepted" };
  if (
    engagement.feedback.some(
      (feedback) =>
        feedback.submission_id === submission.id && feedback.kind === "changes_requested",
    )
  )
    return { text: "Требуются изменения", kind: "changes" };
  if (engagement.submissions[0]?.id !== submission.id)
    return { text: "В истории", kind: "history" };
  if (!submission.ready_for_acceptance) return { text: "Для обсуждения", kind: "discussion" };
  return { text: "Ожидает проверки", kind: "review" };
}

export function VersionCard({
  engagement,
  submission,
  compact = false,
  onComment,
}: {
  engagement: Engagement;
  submission: Submission;
  compact?: boolean;
  onComment: () => void;
}) {
  const [selected, setSelected] = useState(0);
  const images = submission.files.filter((file) => file.content_type.startsWith("image/"));
  const state = versionState(engagement, submission);
  const comments = engagement.feedback.filter(
    (feedback) => feedback.submission_id === submission.id,
  );
  return (
    <article
      className={`workroom-card workroom-version ${compact ? "is-compact" : ""}`}
      aria-label={`Версия ${submission.version}`}
    >
      <div className="workroom-version-body">
        <div className="workroom-version-copy">
          <div className="workroom-version-heading">
            <h3>Версия {submission.version}</h3>
            <span className={`workroom-version-status is-${state.kind}`}>{state.text}</span>
          </div>
          <h4>{submission.title || "Результат работы"}</h4>
          <time dateTime={submission.created_at}>Передана {workTime(submission.created_at)}</time>
          <p className="workroom-version-message">{submission.content}</p>
          <div className="workroom-files">
            {submission.files.map((file) => (
              <WorkFileLink key={file.id} engagementId={engagement.id} file={file} />
            ))}
          </div>
        </div>
        {images.length > 0 && (
          <div className="workroom-gallery">
            <div className="workroom-gallery-main">
              <WorkImage
                engagementId={engagement.id}
                file={images[Math.min(selected, images.length - 1)]}
              />
            </div>
            {images.length > 1 && (
              <div className="workroom-gallery-thumbs">
                {images.map((file, index) => (
                  <button
                    key={file.id}
                    aria-label={`Показать ${file.filename}`}
                    aria-pressed={index === selected}
                    onClick={() => setSelected(index)}
                  >
                    <WorkImage engagementId={engagement.id} file={file} />
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
      {comments.map((feedback) => (
        <div
          key={feedback.id}
          className={`workroom-feedback ${feedback.kind === "changes_requested" ? "is-changes" : ""}`}
        >
          <div>
            <strong>{feedback.actor.display_name}</strong>
            <time dateTime={feedback.created_at}>{workTime(feedback.created_at)}</time>
            {feedback.kind === "changes_requested" && <span>Запрос изменений</span>}
          </div>
          <p>{feedback.content}</p>
        </div>
      ))}
      <div className="workroom-version-footer">
        <button className="workroom-text-link" onClick={onComment}>
          <MessageCircle size={15} />
          Комментарий{comments.length ? ` · ${comments.length}` : ""}
        </button>
        <details>
          <summary>Данные передачи</summary>
          <span>Сохранены название, комментарий, готовность к приёмке и состав файлов.</span>
          {submission.manifest_sha256 && <span>Формат: {submission.manifest_format}</span>}
          <code>SHA-256 {submission.manifest_sha256 ?? submission.sha256}</code>
        </details>
      </div>
    </article>
  );
}

export function Terms({ engagement }: { engagement: Engagement }) {
  const terms = engagement.terms;
  return (
    <div className="workroom-terms-detail">
      <h3>{terms.title}</h3>
      <dl>
        <div>
          <dt>Стоимость</dt>
          <dd>{formatMoney(terms.price_minor, terms.currency)}</dd>
        </div>
        <div>
          <dt>Срок работы</dt>
          <dd>{terms.delivery_days} дней</dd>
        </div>
        <div>
          <dt>Дедлайн брифа</dt>
          <dd>{briefDate(terms.deadline)}</dd>
        </div>
        <div>
          <dt>Комиссия платформы при выплате</dt>
          <dd>{terms.commission_basis_points / 100}%</dd>
        </div>
      </dl>
      <h4>Задача</h4>
      <p>{terms.description}</p>
      {!!terms.deliverables?.length && (
        <>
          <h4>Что нужно передать</h4>
          <ul>
            {terms.deliverables?.map((item, index) => (
              <li key={index}>{item}</li>
            ))}
          </ul>
        </>
      )}
      {terms.expected_result && (
        <>
          <h4>Ожидаемый результат</h4>
          <p>{terms.expected_result}</p>
        </>
      )}
      {!!terms.requirements?.length && (
        <>
          <h4>Требования</h4>
          <ul>
            {terms.requirements?.map((item, index) => (
              <li key={index}>{item}</li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}

export function activity(engagement: Engagement) {
  const rows = [
    {
      id: "agreed",
      at: engagement.created_at,
      title: "Предложение принято, условия зафиксированы",
      kind: "accepted",
    },
  ];
  if (engagement.started_at)
    rows.push({
      id: "started",
      at: engagement.started_at,
      title: "Автор начал работу",
      kind: "work",
    });
  engagement.submissions.forEach((submission) =>
    rows.push({
      id: submission.id,
      at: submission.created_at,
      title: `Передана версия ${submission.version}${submission.title ? ` · ${submission.title}` : ""}`,
      kind: "work",
    }),
  );
  engagement.feedback.forEach((feedback) =>
    rows.push({
      id: feedback.id,
      at: feedback.created_at,
      title: `${feedback.actor.display_name}: ${feedback.kind === "changes_requested" ? "запрошены изменения" : "добавлен комментарий"}${feedback.submission_id ? ` к версии ${engagement.submissions.find((item) => item.id === feedback.submission_id)?.version ?? ""}` : ""}`,
      kind: "comment",
    }),
  );
  if (engagement.accepted_at)
    rows.push({
      id: "accepted",
      at: engagement.accepted_at,
      title: "Результат принят заказчиком",
      kind: "accepted",
    });
  return rows.sort((a, b) => b.at.localeCompare(a.at));
}
export function Activity({ events }: { events: ReturnType<typeof activity> }) {
  return (
    <ol className="workroom-timeline">
      {events.map((event) => (
        <li key={event.id} className={event.kind === "accepted" ? "is-accepted" : ""}>
          <time dateTime={event.at}>{workTime(event.at)}</time>
          <p>{event.title}</p>
        </li>
      ))}
    </ol>
  );
}

export function FeedbackComposer({
  engagement,
  kind,
  submission,
  onClose,
  refresh,
}: {
  engagement: Engagement;
  kind: "comment" | "changes_requested";
  submission: Submission | null;
  onClose: () => void;
  refresh: () => Promise<void>;
}) {
  const command = useCommand();
  async function submit(form: FormData) {
    try {
      await command.execute(`/engagements/${engagement.id}/feedback`, {
        content: String(form.get("content")).trim(),
        kind,
        submission_id: submission?.id ?? null,
      });
      await refresh();
      onClose();
    } catch {}
  }
  return (
    <Modal
      title={kind === "changes_requested" ? "Запросить изменения" : "Комментарий к работе"}
      onClose={() => {
        if (!command.pending) onClose();
      }}
    >
      <p className="workroom-help">
        {submission
          ? `Версия ${submission.version} · ${submission.title || "Результат работы"}`
          : engagement.terms.title}
      </p>
      <form action={submit} className="form-stack">
        <label>
          {kind === "changes_requested" ? "Что нужно изменить" : "Сообщение"}
          <textarea name="content" rows={5} required maxLength={4000} disabled={command.pending} />
        </label>
        {kind === "changes_requested" && (
          <p className="workroom-help">
            Работа вернётся к автору. Ваш отзыв останется в истории этой версии.
          </p>
        )}
        {command.error && (
          <p className="error" role="alert">
            {command.error}
          </p>
        )}
        <button className="button primary" disabled={command.pending}>
          {kind === "changes_requested" ? "Отправить замечания" : "Отправить комментарий"}
          <Send size={17} />
        </button>
      </form>
    </Modal>
  );
}
