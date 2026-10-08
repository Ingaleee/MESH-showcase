import type { components } from "./api-schema";

export type Account = components["schemas"]["Account"];
export type Project = components["schemas"]["Project"];
export type ProjectDetail = components["schemas"]["ProjectDetail"];
export type Profile = components["schemas"]["Profile"];
export type Proposal = components["schemas"]["Proposal"];
export type ProposalExample = components["schemas"]["ProposalExample"];
export type Engagement = components["schemas"]["Engagement"];
export type Submission = components["schemas"]["Submission"];
export type WorkFile = components["schemas"]["WorkFile"];
export type Feedback = components["schemas"]["Feedback"];
export type Finance = components["schemas"]["Finance"];
export type Operations = components["schemas"]["Operations"];
export type Notification = components["schemas"]["Notification"];
export type Session = components["schemas"]["Session"];

let csrfToken = "";
const errorMessages: Record<string, string> = {
  PROFILE_REQUIRED: "Сначала заполните профиль автора на странице «Авторы».",
  STALE_BRIEF: "Бриф изменился. Обновите страницу и подготовьте новое предложение.",
  STALE_VERSION: "Эта версия уже изменилась. Обновите страницу.",
  STALE_SUBMISSION: "Автор передал новую версию. Проверьте её перед приёмкой.",
  ALREADY_AWARDED: "Автор уже выбран. Откройте соглашение в разделе «Моя работа».",
  FORBIDDEN: "У вас нет доступа к этому действию.",
  INVALID_CREDENTIALS: "Проверьте email и пароль.",
  CSRF_INVALID: "Сессия обновилась. Обновите страницу и повторите действие.",
  VALIDATION_ERROR: "Проверьте заполненные поля.",
  PAYOUT_ALREADY_STARTED: "Выплата уже отправлена провайдеру. Спор нужно передать оператору.",
  PAYOUT_HELD: "Сначала нужно разрешить спор.",
  RETRY_LATER: "Сервис занят. Повторите действие немного позже.",
  CAPACITY_LIMIT: "Сервис занят. Подождите немного и повторите действие.",
  RATE_LIMITED: "Слишком много попыток. Подождите несколько минут.",
  INVALID_FILE: "Выберите непустой файл допустимого размера.",
  INVALID_FILE_TYPE:
    "Формат файла не поддерживается. Проверьте допустимые форматы под полем загрузки.",
  FILE_LIMIT: "Удалите неиспользованные примеры перед загрузкой нового файла.",
  FILE_REJECTED: "Файл не прошёл проверку. Удалите его или выберите другой пример.",
  FILE_QUARANTINED: "Файл ещё не прошёл проверку и пока недоступен для скачивания.",
  FILES_NOT_VERIFIED: "Все файлы результата должны пройти проверку перед принятием работы.",
  ALREADY_APPLIED: "Ваше предложение к этой версии брифа уже отправлено.",
  PROJECT_CLOSED: "Заказчик завершил приём предложений.",
  PROPOSALS_PAUSED: "Заказчик приостановил приём предложений. Черновик остаётся у вас.",
  WORK_CLOSED: "Работа завершена. Новую версию передать нельзя.",
  FILE_SUBMITTED: "Файл уже закреплён за версией. Передайте изменения в новой версии.",
  NOT_READY: "Автор передал эту версию для обсуждения и пока не отметил готовность к принятию.",
  CHANGES_REQUESTED: "Для этой версии запрошены изменения. Дождитесь новой передачи.",
  ZIP_LIMIT: "Архив больше 50 МБ. Скачайте файлы отдельно.",
};

export class ApiError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number,
    public readonly requestId?: string,
  ) {
    super(message);
  }
}

export function setCsrfToken(value: string) {
  csrfToken = value;
}

export async function api<T>(
  path: string,
  options: { method?: string; body?: unknown; key?: string } = {},
): Promise<T> {
  const method = options.method ?? "GET";
  const multipart = options.body instanceof FormData;
  const response = await fetch(`/api/v1${path}`, {
    method,
    credentials: "same-origin",
    headers: {
      ...(!multipart ? { "Content-Type": "application/json" } : {}),
      ...(method !== "GET" ? { "X-CSRF-Token": csrfToken } : {}),
      ...(options.key ? { "Idempotency-Key": options.key } : {}),
    },
    ...(options.body
      ? { body: multipart ? (options.body as FormData) : JSON.stringify(options.body) }
      : {}),
  });
  if (response.status === 204) return undefined as T;
  const data = await response.json().catch(() => {
    throw new ApiError(
      "SERVICE_UNAVAILABLE",
      "Сервис временно недоступен. Попробуйте ещё раз.",
      response.status,
    );
  });
  if (!response.ok) {
    throw new ApiError(
      data.code ?? "REQUEST_FAILED",
      errorMessages[data.code] ?? data.message ?? "Не удалось выполнить запрос.",
      response.status,
      data.request_id,
    );
  }
  return data as T;
}

export function formatMoney(minor: number, currency = "RUB") {
  const digits = currency === "JPY" ? 0 : 2;
  return new Intl.NumberFormat("ru-RU", {
    style: "currency",
    currency,
    maximumFractionDigits: digits,
    minimumFractionDigits: 0,
  }).format(minor / 10 ** digits);
}

export const categories = ["Все проекты", "Тексты", "Дизайн", "Видео", "Разработка", "Маркетинг"];
