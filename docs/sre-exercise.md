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

Threshold 3 seconds/hold 3 seconds намеренно ускоряют controlled drill. Production alerts в infra/alerts.yml имеют более длинные окна. Synthetic fault не является измерением production reliability. Receiver хранит только redacted receipts в tmpfs; evidence нужно снять до его остановки. Никакие Slack/email/внешние сообщения не отправляются.

При расследовании: /ready и queue_up должны оставаться healthy; очередь events растёт, worker stopped; DB/outbox не потеряли intent. После старта worker queue drains, effects_per_event=[1], alert resolves. Доказательство должно включать доставленные firing/resolved receipts и времена обнаружения/восстановления.

Начальные SLO proposals: 99.5% успешных eligible read requests за 30 дней; 99% notifications доставлены за 60 секунд; 99% files вышли из quarantine за 5 минут при поддерживаемом размере и доступном scanner. На сейчас HTTP availability/latency histogram ещё нет, поэтому первый SLO нельзя объявлять измеренным. Queue gauges дают operational alerts, но не точный delivery percentile SLI. Следующее Ruby telemetry изменение должно измерить event delivery latency histogram без actor/project labels.

EN support update template: "We reproduced delayed notifications in the isolated environment. Accepted events remained durable; the worker was not consuming the queue. We restored the worker, verified one notification per event, and observed the alert resolve. No external payout was initiated. We are adding a regression check and documenting the queue recovery procedure." Использовать только после фактически законченного exercise.
