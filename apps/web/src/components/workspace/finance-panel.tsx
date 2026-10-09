"use client";

import { useCallback, useEffect, useState } from "react";
import { Wallet } from "lucide-react";
import { api, formatMoney, type Engagement, type Finance } from "@/lib/api";
import { useCommand } from "@/lib/use-command";
import { Modal } from "@/components/modal";

const states: Record<string, string> = {
  requested: "В очереди",
  dispatching: "Отправляется",
  unknown: "Уточняем результат",
  confirmed: "Подтверждено",
  failed: "Отклонено",
};

export function FinancePanel({ engagement, actorId }: { engagement: Engagement; actorId: string }) {
  const [finance, setFinance] = useState<Finance | null>(null);
  const [financeError, setFinanceError] = useState("");
  const [scenario, setScenario] = useState("normal");
  const [hold, setHold] = useState(false);
  const command = useCommand();
  const client = actorId === engagement.client_id;
  const fetchFinance = useCallback(
    () =>
      api<Finance>(`/engagements/${engagement.id}/finance`)
        .then((result) => {
          setFinance(result);
          setFinanceError("");
        })
        .catch((failure: Error) => setFinanceError(failure.message)),
    [engagement.id],
  );
  useEffect(() => {
    void fetchFinance();
    const timer = setInterval(fetchFinance, 3000);
    return () => clearInterval(timer);
  }, [fetchFinance]);
  async function payment(kind: string) {
    try {
      await command.execute(`/engagements/${engagement.id}/finance`, { kind, scenario });
      await fetchFinance();
    } catch {}
  }
  async function placeHold(form: FormData) {
    try {
      await command.execute(`/engagements/${engagement.id}/hold`, { reason: form.get("reason") });
      setHold(false);
      await fetchFinance();
    } catch {}
  }
  return (
    <div className="workroom-finance">
      <section className="panel">
        <div className="section-heading">
          <h2>
            <Wallet size={20} />
            Расчёты
          </h2>
          <span className="sandbox-badge">СИМУЛЯТОР · БЕЗ РЕАЛЬНЫХ ДЕНЕГ</span>
        </div>
        <p className="muted small">
          Демо платёжного процесса. Комиссия удерживается при выплате; здесь не принимаются
          банковские данные.
        </p>
        {financeError && (
          <p className="error" role="alert">
            {financeError}
          </p>
        )}
        {finance && (
          <>
            {finance.settlement?.hold && (
              <p className="error">Выплата приостановлена: {finance.settlement.hold_reason}</p>
            )}
            <div className="payment-timeline">
              {finance.operations.length === 0 ? (
                <p className="muted">Пока нет операций.</p>
              ) : (
                finance.operations.map((operation) => (
                  <div className="payment-row" key={operation.id}>
                    <span>
                      {operation.kind === "fund" ? "Резервирование" : "Выплата автору"}
                      <small>{operation.attempts} попыток</small>
                    </span>
                    <strong>{formatMoney(operation.amount_minor, operation.currency)}</strong>
                    <span
                      className={`status-pill ${operation.state === "unknown" ? "warning" : ""}`}
                    >
                      {states[operation.state]}
                    </span>
                  </div>
                ))
              )}
            </div>
            {client && (
              <div className="payment-actions">
                <label>
                  Сценарий симулятора
                  <select value={scenario} onChange={(event) => setScenario(event.target.value)}>
                    <option value="normal">Обычное подтверждение</option>
                    <option value="timeout_after_success">Списание успешно, ответ потерян</option>
                    <option value="decline">Провайдер отклонил операцию</option>
                  </select>
                </label>
                <div className="button-row">
                  {!finance.operations.some((item) => item.kind === "fund") && (
                    <button
                      className="button primary"
                      disabled={command.pending}
                      onClick={() => {
                        void payment("fund");
                      }}
                    >
                      Зарезервировать сумму
                    </button>
                  )}
                  {finance.settlement?.funded &&
                    engagement.state === "accepted" &&
                    !finance.operations.some((item) => item.kind === "payout") && (
                      <button
                        className="button primary"
                        disabled={command.pending || finance.settlement.hold}
                        onClick={() => {
                          void payment("payout");
                        }}
                      >
                        Выплатить автору
                      </button>
                    )}
                </div>
              </div>
            )}
            {!finance.settlement?.hold &&
              !finance.operations.some(
                (item) =>
                  item.kind === "payout" &&
                  ["dispatching", "unknown", "confirmed"].includes(item.state),
              ) && (
                <button className="text-button" onClick={() => setHold(true)}>
                  Возник спор? Приостановить выплату
                </button>
              )}
            {finance.operations.some((item) => item.state === "unknown") && (
              <div className="info-note">
                Ответ провайдера не получен. MESH проверяет результат по прежнему идентификатору
                операции. Повторная выплата не создаётся.
              </div>
            )}
            <details className="ledger-details">
              <summary>История проводок · {finance.ledger.length}</summary>
              {finance.ledger.map((journal) => (
                <div key={journal.id} className="journal">
                  <strong>{journal.description}</strong>
                  {journal.entries.map((entry, index) => (
                    <div key={index}>
                      <code>{entry.account_key}</code>
                      <span>
                        {entry.direction === "debit" ? "Дт" : "Кт"}{" "}
                        {formatMoney(entry.amount_minor, entry.currency)}
                      </span>
                    </div>
                  ))}
                </div>
              ))}
            </details>
          </>
        )}
      </section>
      {command.error && (
        <p className="error" role="alert">
          {command.error}
        </p>
      )}
      {hold && (
        <Modal title="Приостановить выплату" onClose={() => setHold(false)}>
          <p className="muted">
            Опишите причину спора. Решение и снятие блокировки фиксируются в истории.
          </p>
          <form action={placeHold} className="form-stack">
            <label>
              Причина
              <textarea name="reason" required minLength={5} maxLength={2000} rows={4} />
            </label>
            {command.error && (
              <p className="error" role="alert">
                {command.error}
              </p>
            )}
            <button className="button primary" disabled={command.pending}>
              Зафиксировать спор
            </button>
          </form>
        </Modal>
      )}
    </div>
  );
}
