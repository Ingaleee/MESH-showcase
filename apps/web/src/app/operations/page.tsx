"use client";

import { useEffect, useState } from "react";
import { Activity, RefreshCw, ShieldCheck } from "lucide-react";
import { api, type Operations } from "@/lib/api";
import { useSession } from "@/components/session-provider";
import { useCommand } from "@/lib/use-command";

const labels: Record<string, string> = {
  pending_deliveries: "Ожидают доставки",
  oldest_delivery_seconds: "Возраст очереди, с",
  processed_deliveries: "Событий доставлено",
  unknown_payments: "Платежей уточняется",
  reconciliation_exceptions: "Расхождений",
  ledger_transactions: "Журналов проведено",
};
export default function OperationsPage() {
  const { account, openLogin } = useSession();
  const [data, setData] = useState<Operations | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const command = useCommand();
  function refresh() {
    return api<Operations>("/operations")
      .then(setData)
      .catch((failure: Error) => setError(failure.message));
  }
  useEffect(() => {
    if (!account?.operator) return;
    void refresh();
    const timer = setInterval(refresh, 5000);
    return () => clearInterval(timer);
  }, [account]);
  async function reconcile() {
    try {
      const result = await command.execute<{
        checked: number;
        recovered: number;
        exceptions: number;
      }>("/operations/reconcile");
      setNotice(
        `Проверено: ${result.checked}. Восстановлено: ${result.recovered}. Расхождений: ${result.exceptions}.`,
      );
      await refresh();
    } catch {}
  }
  return (
    <div className="page-container">
      <div className="page-heading">
        <div>
          <span className="eyebrow">СОСТОЯНИЕ ПЛАТФОРМЫ</span>
          <h1>
            Операционный пульт<span className="violet">.</span>
          </h1>
        </div>
        {account?.operator && (
          <button
            className="button primary"
            disabled={command.pending}
            onClick={() => {
              void reconcile();
            }}
          >
            <RefreshCw size={16} />
            Сверить с провайдером
          </button>
        )}
      </div>
      {!account?.operator ? (
        <div className="panel empty-state">
          <ShieldCheck size={30} />
          <h2>Доступ для оператора</h2>
          <p>История событий и расчётов доступна назначенным операторам.</p>
          {!account && (
            <button className="button primary" onClick={openLogin}>
              Войти
            </button>
          )}
        </div>
      ) : (
        <>
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
          {data && (
            <>
              <div className="metrics-grid">
                {Object.entries(data.metrics).map(([key, value]) => (
                  <article className="panel metric" key={key}>
                    <Activity size={17} />
                    <strong>{value}</strong>
                    <span>{labels[key]}</span>
                  </article>
                ))}
              </div>
              <div className="section-spaced panel">
                <h2>Журнал событий</h2>
                <div className="table-scroll">
                  <table>
                    <thead>
                      <tr>
                        <th>Событие</th>
                        <th>Correlation ID</th>
                        <th>Время</th>
                      </tr>
                    </thead>
                    <tbody>
                      {data.events.map((event) => (
                        <tr key={event.id}>
                          <td>{event.event_type}</td>
                          <td>
                            <code>{event.correlation_id}</code>
                          </td>
                          <td>{new Date(event.created_at).toLocaleTimeString("ru-RU")}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
              <div className="section-spaced panel">
                <h2>Аудит действий</h2>
                <div className="table-scroll">
                  <table>
                    <thead>
                      <tr>
                        <th>Действие</th>
                        <th>Ресурс</th>
                        <th>Время</th>
                      </tr>
                    </thead>
                    <tbody>
                      {data.audit.map((entry) => (
                        <tr key={entry.id}>
                          <td>{entry.action}</td>
                          <td>
                            <code>{entry.resource_id}</code>
                          </td>
                          <td>{new Date(entry.created_at).toLocaleTimeString("ru-RU")}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
              {data.deliveries.length > 0 && (
                <section className="panel section-spaced">
                  <h2>Необработанные доставки</h2>
                  {data.deliveries.map((delivery) => (
                    <div className="payment-row" key={delivery.id}>
                      <code>{delivery.id.slice(0, 8)}</code>
                      <span>
                        {delivery.state} · {delivery.attempts} попыток
                      </span>
                      {delivery.state === "failed" && (
                        <button
                          className="button compact"
                          onClick={async () => {
                            try {
                              await command.execute(`/operations/deliveries/${delivery.id}/retry`);
                              await refresh();
                            } catch {}
                          }}
                        >
                          Повторить
                        </button>
                      )}
                    </div>
                  ))}
                </section>
              )}
            </>
          )}
        </>
      )}
    </div>
  );
}
