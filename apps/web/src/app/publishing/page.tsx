"use client";

import { useEffect, useState, useCallback } from "react";
import {
  ArrowUpRight,
  Check,
  FileArchive,
  Fingerprint,
  FlaskConical,
  RefreshCw,
  ShieldCheck,
  UploadCloud,
  X,
} from "lucide-react";
import { api } from "@/lib/api";
import type { components } from "@/lib/api-schema";
import { useSession } from "@/components/session-provider";
import { useCommand } from "@/lib/use-command";
import "./publishing.css";

type Overview = components["schemas"]["PublishingOverview"];
type Diagnostic = components["schemas"]["PublishingDiagnostic"];
const labels: Record<string, string> = {
  pending: "В очереди",
  running: "Проверяем",
  passed: "Проверка пройдена",
  rejected: "Отклонён",
  failed: "Нужна помощь",
  dispatching: "Отправляем",
  unknown: "Уточняем исход",
  confirmed: "Подтверждён",
};
export default function PublishingPage() {
  const { account, openLogin } = useSession();
  const [data, setData] = useState<Overview | null>(null);
  const [selected, setSelected] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [diagnostic, setDiagnostic] = useState<Diagnostic | null>(null);
  const [zip, setZip] = useState<File | null>(null);
  const [manifest, setManifest] = useState<File | null>(null);
  const command = useCommand();
  const [historyCursors, setHistoryCursors] = useState<Record<string, string>>({});
  const refresh = useCallback(async () => {
    try {
      const query = new URLSearchParams(historyCursors).toString();
      const result = await api<Overview>("/publishing" + (query ? "?" + query : ""));
      setData(result);
      setError("");
      setSelected((previous) =>
        result.candidates.some((row) => row.id === previous)
          ? previous
          : (result.candidates[0]?.id ?? ""),
      );
    } catch (failure) {
      setError((failure as Error).message);
    }
  }, [historyCursors]);
  useEffect(() => {
    if (!account?.operator) return;
    void refresh();
    const timer = setInterval(() => void refresh(), 3000);
    return () => clearInterval(timer);
  }, [account, refresh]);
  const candidate = data?.candidates.find((row) => row.id === selected);
  const validation = data?.validations.find((row) => row.candidate_id === selected);
  const releases = data?.deployments.filter((row) => row.candidate_id === selected) ?? [];
  const active = data?.active_deployments.find((row) =>
    data.partners.some((partner) => partner.active_deployment_id === row.id),
  );
  async function upload() {
    if (!zip || !manifest || !data?.partners[0]) return;
    try {
      const body = new FormData();
      body.append("artifact", zip);
      body.append("manifest", await manifest.text());
      const result = await command.execute<{ id: string }>(
        "/publishing/partners/" + data.partners[0].id + "/candidates",
        body,
      );
      setSelected(result.id);
      setNotice("Пакет принят. Проверка выполняется в рабочей очереди.");
      setZip(null);
      setManifest(null);
      await refresh();
    } catch {}
  }
  async function publish() {
    if (!candidate || !validation) return;
    try {
      await command.execute("/publishing/candidates/" + candidate.id + "/publish", {
        validation_id: validation.id,
      });
      setNotice("Выпуск поставлен в очередь.");
      await refresh();
    } catch {}
  }
  async function revalidate() {
    if (!candidate) return;
    try {
      await command.execute("/publishing/candidates/" + candidate.id + "/validate", {});
      await refresh();
    } catch {}
  }
  return (
    <div className="page-container publishing-page">
      <div className="pub-heading">
        <div>
          <span className="eyebrow">MESH / ENGINEERING SHOWCASE</span>
          <h1>
            Integration &amp;
            <br />
            <span className="violet">Release Lab.</span>
          </h1>
          <p>
            От пакета студии до подтверждённого выпуска.
            <br />
            Каждое решение — с проверкой и историей.
          </p>
        </div>
        <div className="pub-hero-mark" aria-hidden="true">
          <FlaskConical size={60} />
          <span>
            VALIDATE
            <br />
            PUBLISH
            <br />
            OBSERVE
          </span>
        </div>
      </div>
      {!account?.operator ? (
        <section className="panel empty-state">
          <ShieldCheck size={34} />
          <h2>Рабочее место оператора</h2>
          <p>Интеграции доступны назначенным операторам.</p>
          {!account && (
            <button className="button primary" onClick={openLogin}>
              Войти
            </button>
          )}
        </section>
      ) : (
        <>
          <div className="pub-journey" aria-label="Этапы выпуска">
            {["Пакет", "Проверка", "Выпуск", "Наблюдение"].map((step, i) => (
              <div key={step}>
                <span>{String(i + 1).padStart(2, "0")}</span>
                <strong>{step}</strong>
                {i < 3 && <ArrowUpRight size={16} />}
              </div>
            ))}
          </div>
          {(error || command.error) && (
            <p className="error" role="alert">
              {error || command.error}
            </p>
          )}
          {notice && (
            <p className="success" role="status">
              {notice}
            </p>
          )}
          <div className="pub-stats">
            <article>
              <small>ПРОВЕРЕНО</small>
              <strong>
                {data?.validations.filter(
                  (row) => row.state === "passed" && row.current_inputs_match,
                ).length ?? "—"}
              </strong>
              <span>успешных проверок в выборке</span>
            </article>
            <article>
              <small>АКТИВНЫЙ ВЫПУСК</small>
              <strong>{active?.remote_sequence ? "#" + active.remote_sequence : "—"}</strong>
              <span>
                {active?.kind === "rollback" ? "подтверждённый откат" : "подтверждён партнёром"}
              </span>
            </article>
            <article className="pub-stat-violet">
              <small>НЕОПРЕДЕЛЁННЫЙ ИСХОД</small>
              <strong>
                {data?.deployments.filter((row) => row.state === "unknown").length ?? "—"}
              </strong>
              <span>требует сверки с партнёром</span>
            </article>
          </div>
          <div className="pub-columns">
            <section>
              <div className="pub-section-title">
                <h2>Кандидаты на выпуск</h2>
                <button
                  className="button ghost"
                  onClick={() => void refresh()}
                  aria-label="Обновить данные"
                >
                  <RefreshCw size={17} />
                </button>
              </div>
              <p className="pub-muted">До 30 пакетов на странице · приватные артефакты</p>
              <div className="pub-section-title">
                <button className="button ghost" onClick={() => setHistoryCursors({})}>
                  Новые записи
                </button>
                {data?.next_cursors.candidates && (
                  <button
                    className="button ghost"
                    onClick={() =>
                      setHistoryCursors((value) => ({
                        ...value,
                        candidates_cursor: data.next_cursors.candidates!,
                      }))
                    }
                  >
                    Предыдущие пакеты
                  </button>
                )}
                {data?.next_cursors.partners && (
                  <button
                    className="button ghost"
                    onClick={() =>
                      setHistoryCursors((value) => ({
                        ...value,
                        partners_cursor: data.next_cursors.partners!,
                      }))
                    }
                  >
                    Другие студии
                  </button>
                )}
              </div>
              <div
                className="pub-candidates"
                role="region"
                aria-label="Последние пакеты студий"
                tabIndex={0}
              >
                {data?.candidates.map((row) => {
                  const run = data.validations.find((item) => item.candidate_id === row.id);
                  return (
                    <button
                      key={row.id}
                      className={"pub-candidate " + (selected === row.id ? "selected" : "")}
                      onClick={() => {
                        setSelected(row.id);
                        setDiagnostic(null);
                      }}
                    >
                      <div className="pub-file-icon">
                        <FileArchive size={25} />
                      </div>
                      <div>
                        <strong>{row.manifest.title}</strong>
                        <span>
                          Версия {row.manifest.version} · contract {row.manifest.contract_version}
                        </span>
                        <code>{row.artifact_sha256.slice(0, 16)}…</code>
                      </div>
                      <span className={"pub-state " + run?.state}>
                        {labels[run?.state ?? "pending"]}
                      </span>
                    </button>
                  );
                })}
                {data && !data.candidates.length && (
                  <div className="panel empty-state">
                    <FileArchive size={32} />
                    <h3>Первый пакет — начало истории</h3>
                    <p>Загрузите ZIP и manifest.</p>
                  </div>
                )}
              </div>
              <section className="pub-upload panel">
                <UploadCloud size={24} />
                <div>
                  <h3>Новый пакет студии</h3>
                  <p>ZIP до 2 MB · manifest-v1 · обязательный index.html</p>
                </div>
                <label>
                  ZIP-артефакт
                  <input
                    type="file"
                    accept=".zip"
                    onChange={(event) => setZip(event.target.files?.[0] ?? null)}
                  />
                </label>
                <label>
                  Manifest JSON
                  <input
                    type="file"
                    accept=".json"
                    onChange={(event) => setManifest(event.target.files?.[0] ?? null)}
                  />
                </label>
                <button
                  className="button primary"
                  onClick={() => void upload()}
                  disabled={!zip || !manifest || !data?.partners.length || command.pending}
                >
                  Отправить на проверку <ArrowUpRight size={16} />
                </button>
                {!data?.partners.length && (
                  <p className="pub-muted">Подготовьте партнёра командой demo или Ruby CLI.</p>
                )}
              </section>
            </section>
            <section className="pub-detail panel">
              <div className="pub-section-title">
                <div>
                  <span className="eyebrow">VALIDATION REPORT</span>
                  <h2>{candidate?.manifest.title ?? "Выберите пакет"}</h2>
                </div>
                <ShieldCheck size={25} />
              </div>
              {candidate && (
                <>
                  <div className="pub-digest">
                    <Fingerprint size={18} />
                    <div>
                      <small>SHA-256 проверяемого артефакта</small>
                      <code>{candidate.artifact_sha256}</code>
                    </div>
                  </div>
                  <div className="pub-report-meta">
                    <span>
                      Политика <b>{validation?.policy_version ?? data?.policy_version}</b>
                    </span>
                    <span className={"pub-state " + validation?.state}>
                      {labels[validation?.state ?? "pending"]}
                    </span>
                  </div>
                  <div className="pub-checks">
                    {validation?.report.checks?.map((row, index) => (
                      <article key={row.code + index}>
                        <span className={row.ok ? "pub-check-ok" : "pub-check-fail"}>
                          {row.ok ? <Check size={14} /> : <X size={14} />}
                        </span>
                        <div>
                          <strong>{row.code}</strong>
                          <p>{row.ok ? row.observed : row.fix}</p>
                          {!row.ok && <small>Ожидалось: {row.expected}</small>}
                        </div>
                      </article>
                    ))}
                  </div>
                  {!validation?.report.checks?.length && (
                    <p className="pub-muted">
                      Worker сформирует отчёт после проверки bytes и HTTP-контракта.
                    </p>
                  )}
                  {validation?.last_error && <p className="error">{validation.last_error}</p>}
                  {validation && !validation.current_inputs_match && (
                    <p className="error" role="status">
                      Настройки проверки изменились. Проверьте пакет по текущим правилам перед
                      выпуском.
                    </p>
                  )}
                  <div className="pub-actions">
                    <button
                      className="button primary"
                      disabled={
                        validation?.state !== "passed" ||
                        !validation.current_inputs_match ||
                        command.pending
                      }
                      onClick={() => void publish()}
                    >
                      Выпустить эту версию <ArrowUpRight size={17} />
                    </button>
                    <button
                      className="button ghost"
                      onClick={() => void revalidate()}
                      disabled={command.pending}
                    >
                      Проверить снова
                    </button>
                  </div>
                  <p className="pub-muted">
                    Выпуск разрешён для проверенного digest и актуальных входов проверки.
                  </p>
                  <div className="pub-section-title pub-history-title">
                    <h3>История выпусков</h3>
                    <span>{releases.length}</span>
                  </div>
                  {releases.map((row) => (
                    <article className="pub-release" key={row.id}>
                      <div>
                        <strong>
                          {row.kind === "rollback" ? "Откат к этой версии" : "Выпуск версии"}{" "}
                          {row.remote_sequence ? "#" + row.remote_sequence : ""}
                        </strong>
                        <span className={"pub-state " + row.state}>{labels[row.state]}</span>
                        <code>{row.id}</code>
                      </div>
                      <button
                        className="button ghost"
                        onClick={() => {
                          void api<Diagnostic>("/publishing/deployments/" + row.id + "/diagnose")
                            .then(setDiagnostic)
                            .catch((failure) => setError(failure.message));
                        }}
                      >
                        Диагностика
                      </button>
                      {row.state === "unknown" && (
                        <button
                          className="button ghost"
                          onClick={() => {
                            void command
                              .execute("/publishing/deployments/" + row.id + "/reconcile", {})
                              .then(refresh)
                              .catch(() => {});
                          }}
                        >
                          Сверить состояние
                        </button>
                      )}
                      {row.state === "confirmed" && row.kind === "publish" && (
                        <button
                          className="button ghost"
                          disabled={command.pending}
                          onClick={() => {
                            void command
                              .execute("/publishing/candidates/" + row.candidate_id + "/publish", {
                                validation_id: row.validation_id,
                                rollback_of_id: row.id,
                              })
                              .then(refresh)
                              .catch(() => {});
                          }}
                        >
                          Выпустить как откат
                        </button>
                      )}
                    </article>
                  ))}
                  {data?.next_cursors.deployments && (
                    <button
                      className="button ghost"
                      onClick={() =>
                        setHistoryCursors((value) => ({
                          ...value,
                          deployments_cursor: data.next_cursors.deployments!,
                        }))
                      }
                    >
                      Предыдущие выпуски
                    </button>
                  )}
                  {diagnostic && (
                    <aside className="pub-diagnostic">
                      <span className="eyebrow">READ-ONLY DIAGNOSTICS</span>
                      <h3>{labels[diagnostic.state]}</h3>
                      <p>{diagnostic.next_action}</p>
                      <dl>
                        <dt>Попыток</dt>
                        <dd>{diagnostic.attempts}</dd>
                        <dt>Последний код</dt>
                        <dd>{diagnostic.last_error ?? "—"}</dd>
                        <dt>Входы проверки актуальны</dt>
                        <dd>{diagnostic.current_inputs_match ? "Да" : "Нет"}</dd>
                      </dl>
                      <code>{diagnostic.reproduce}</code>
                      <small>Correlation: {diagnostic.correlation_id}</small>
                    </aside>
                  )}
                </>
              )}
            </section>
          </div>
          <div className="pub-footer">
            <FlaskConical size={19} />
            <p>
              Изолированная лаборатория · независимый TypeScript-партнёр · загруженный код не
              исполняется
            </p>
            <a href="http://localhost:3216/launch" target="_blank" rel="noreferrer">
              Partner preview <ArrowUpRight size={16} />
            </a>
          </div>
        </>
      )}
    </div>
  );
}
