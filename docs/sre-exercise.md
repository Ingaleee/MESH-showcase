# Проверяемая авария очереди

Сценарий только в mesh-showcase-release: остановить worker, принять 50 synthetic durable events, увидеть ожидание в очереди, получить local Alertmanager webhook, восстановить worker, проверить ровно один notification effect на event и resolved webhook.

```powershell
node scripts/prepare-sre.mjs
docker compose --env-file .cache/incident/runtime.env -f infra/sre/compose.yaml up -d
docker compose --env-file .cache/deployment/runtime.env -f infra/deploy/compose.yaml -p mesh-showcase-release stop worker
docker compose --env-file .cache/deployment/runtime.env -f infra/deploy/compose.yaml -p mesh-showcase-release exec -T -e MESH_DEPLOYMENT_PROBE=true api bundle exec ruby script/incident_probe.rb burst
# Wait for delivered firing webhook, not just a Prometheus firing label.
docker compose --env-file .cache/deployment/runtime.env -f infra/deploy/compose.yaml -p mesh-showcase-release start worker
docker compose --env-file .cache/deployment/runtime.env -f infra/deploy/compose.yaml -p mesh-showcase-release exec -T -e MESH_DEPLOYMENT_PROBE=true api bundle exec ruby script/incident_probe.rb drain
```

Threshold 3 seconds/hold 3 seconds намеренно ускоряют controlled drill. Production alerts в infra/alerts.yml имеют более длинные окна. Synthetic fault не является измерением production reliability. Receiver хранит sanitized receipts в persistent volume, в двух ограниченных файлах. Prometheus и Alertmanager также используют durable volumes с ограниченной retention. Это сохраняет историю после restart процесса. Никакие Slack/email/внешние сообщения не отправляются.

При расследовании: /ready и queue_up должны оставаться healthy; очередь events растёт, worker stopped; DB/outbox не потеряли intent. После старта worker queue drains, effects_per_event=[1], alert resolves. Доказательство должно включать доставленные firing/resolved receipts и времена обнаружения/восстановления.

HTTP latency/count уже измеряются process-local histogram с ограниченными controller/action/method/status labels. Notification delivery и validation completion сохраняются в primary DB вместе с terminal effect; replay не увеличивает счётчик. Для общих DB counters dashboard использует max между API replicas, а не складывает копии. Delivery означает создание DB notification, не получение WebSocket или прочтение пользователем.

Лабораторные цели: zero HTTP errors на четырёх маршрутах во время остановки worker; 50/50 notifications с одним effect; доставленные firing и resolved; сохранённый исторический scrape после restart. Длительность, queue threshold и фактическое время обнаружения указаны в отчёте упражнения.

Для будущего 30-day SLO denominator HTTP — валидные запросы поддерживаемых journeys; ожидаемые authorization/business rejections считаются отдельно от 5xx/timeouts. Async denominator должен включать все принятые durable events, включая ещё не завершённые: histogram только завершённых effects не доказывает 99% delivery. Queue oldest age дополняет его сигналом незавершённой работы. Validation histogram аналогично описывает завершённые проверки, не долю всех принятых пакетов. Отсутствие событий не считается 100% доступностью. Production targets/error budget за 30 дней пока не измерены; лабораторный профиль не подменяет это окно.

EN support update template: "We reproduced delayed notifications in the isolated environment. Accepted events remained durable; the worker was not consuming the queue. We restored the worker, verified one notification per event, and observed the alert resolve. No external payout was initiated. We are adding a regression check and documenting the queue recovery procedure." Использовать только после фактически законченного exercise.
