# Надёжность и расследование интеграции

## Что видит оператор

В Publishing UI есть candidate, текущий отчёт с stable error codes, ожидаемым/фактическим значением и исправлением, история deployments и diagnostic report. Stale validation показана отдельно; кнопка выпуска заблокирована до новой проверки. Путь проходит реальный API и очередь.

HTTP histogram ограничен controller/action/method/status labels. Dynamic IDs, email и URL не создают бесконечную cardinality. Notification delivery и validation completion записываются в primary DB в одной transaction с terminal effect. Повторный job не увеличивает histogram второй раз.

[Рабочий dashboard](http://localhost:32092/d/mesh-reliability) использует настоящий Prometheus: HTTP latency/count, notification latency, validation latency, очередь и publishing states. HTTP counters локальны процессу и сбрасываются при restart. Durable histogram общий для API replicas, поэтому PromQL не суммирует один DB counter несколько раз. Финальные notification buckets заканчиваются 60s, HTTP — 10s: quantile приблизителен и имеет ограничения при более долгих задержках. Production SLO/error budget ещё не измерены.

Notification latency означает создание DB notification из durable event. WebSocket доставка/чтение пользователем этой метрикой не доказаны.

## Контролируемый worker incident

```powershell
npm run demo:incident
```

Скрипт ограничен собственным showcase. Останавливает worker, создаёт 50 synthetic events, проверяет HTTP, ждёт доставленный authenticated alert, запускает worker, проверяет по одному effect на event и отсутствие роста counters после replay. В finally пытается вернуть worker.

[Повторный run на исправленных образах](evidence/publishing-incident-patched/summary.json): четыре маршрута вернули 200; firing receipt через 49,517s; 50 effects, 50 новых durable observations, 0 observations от replay; доставлен resolved receipt. Это измерение данного run на shared host с lab threshold queue age >10s for 5s, не гарантированные detection/RTO.

Incident alert receiver доступен только внутри Docker network и требует token. Нет Slack/email и внешних сообщений. Grafana anonymous Viewer открыта только на loopback, административный пароль сгенерирован и не выводится.

## RU postmortem: потерянный ответ партнёра

**Симптом:** deployment unknown, error HTTP_TIMEOUT; у оператора нет достоверного подтверждения.

**Данные:** diagnostic связывает operation_id, correlation_id, artifact digest, validation fingerprint, attempts и next_action. На независимом partner тот же operation_id уже durable confirmed; число publish requests после reconcile не растёт.

**Причина упражнения:** failpoint сначала фиксирует пакет/operation в SQLite, затем задерживает HTTP response дольше общего бюджета Ruby client. Timeout описывает отсутствие ответа, а не отмену операции.

**Восстановление:** GET lookup по существующему operation_id; сравнение identity/digest/sequence; подтверждение local history и monotonic active pointer. Повторный POST не используется.

**Защита:** durable intent до I/O, idempotent partner contract, claim fencing, signed callbacks, консервативный unknown и bounded reconciliation. Если partner lookup недоступен, состояние остаётся неопределённым до получения проверяемых данных. Доказывать успех по отсутствию исключения нельзя.

**Результат:** [CLI drill](evidence/publishing-repeatable-demo/publishing-demo/summary.json) сохранил три POST для v1, v2 и rollback; три файла прошли private SHA verification. Это synthetic integration, не production incident внешней студии.

## EN partner support update

We reproduced a timeout after the partner had durably accepted the package. We kept the original operation ID and reconciled its status through the lookup endpoint. The artifact digest and sequence matched, so we confirmed the local deployment without sending another publish request. The diagnostic report includes the correlation ID, validation policy and next action. This was a controlled simulator exercise; no external studio was contacted.

## Эксплуатационные границы

Local alerts/dashboard используют временные TSDB/SQLite paths и не заменяют долгосрочный monitoring retention. Single-node Kubernetes, одна primary DB и local-path PVC не дают физическую HA. Backup+files restore уже проверен отдельно; offsite/encryption/PITR нужны после выбора среды. Секреты в ignored files не являются промышленным secret manager. Обновления образов требуют нового exact scan и repeatable evidence.
