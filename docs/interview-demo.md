# Демонстрация MESH-showcase за 15 минут

Перед собеседованием из MESH-showcase выполните npm run demo. Откройте [Publishing](http://localhost:3200/publishing), [Grafana](http://localhost:32092/d/mesh-reliability), [каталог evidence](execution-status.md). Не стройте образы и большой dataset впервые перед интервьюером. Команда подготовки сохраняет данные; новые упражнения создают synthetic records.

| Время     | Демонстрация                                                                      | Главный инженерный аргумент                                                                         |
| --------- | --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| 0–2 min   | Бриф → предложение → выбор автора → версия → приёмка                              | Ruby transaction, authorization, fixed agreement terms и ограничения БД                             |
| 2–4 min   | 50k fanout benchmark и query plans                                                | Materialization 50 000 → 20; keyset scope/ties; exact COUNT имеет цену                              |
| 4–7 min   | Publishing: defective ZIP → error code → исправленный кандидат → release          | Проверяются конкретные bytes/digest под конкретной policy/config, не абстрактное имя версии         |
| 7–10 min  | HTTP_TIMEOUT → unknown → diagnostic → lookup → confirmed                          | Неопределённость после I/O; нельзя повторить POST только из-за timeout; партнёр хранит operation ID |
| 10–12 min | Остановить worker, смотреть очередь/HTTP/alert, восстановить                      | HTTP health отдельно от полезной работы; durable effects и replay без дублей                        |
| 12–14 min | Exact image scan, HTTPS release/rollback, Kubernetes drift/deny/recovery evidence | Digest chain, роль миграций, image rollback отдельно от DB; различие readiness и liveness           |
| 14–15 min | DB+private-files recovery и tradeoffs                                             | Hash/download proof, quiescent backup boundary; HA/PITR/offsite и GitHub runs пока отдельная работа |

Worker exercise запускается npm run demo:incident и обычно укладывается в 1–2 минуты на этом host. Если timing изменился, показывайте сохранённый report с реальными timestamps, а не обещайте гарантированное время.

CLI drill npm run demo:publishing печатает operation IDs и diagnostic JSON. Для ручного просмотра — команды [Publishing lab](publishing-lab.md). Полные подписи/credential bytes не демонстрируются. Synthetic operator: ops@mesh.local / MeshDemo2026!.

## Что открыть в Ruby

RequestDeployment показывает короткую transaction и idempotency; ProcessDeployment — I/O вне lock/transaction и fenced claim; ApplyObservation — связывание remote identity, bytes и sequence; ReceiveCallback — подпись, replay и monotonic state. Затем показать SQL triggers/composite FK и настоящий regression test. Steep сейчас проверяет Money boundary, не весь backend.

Объясните компромиссы: modular monolith упрощает согласованность; durable polling подходит этому объёму, но имеет стоимость; 2 MB ZIP ограничивает нагрузку и хранится через private Active Storage, большие artifacts требуют другой storage стратегии; reconciliation возможен только при соответствующем partner contract; Alpine принят после native suite, не ради меньшего размера; local Kubernetes не доказывает HA.

[RU postmortem и EN partner update](publishing-reliability.md) — synthetic exercises. Две истории о вашем реальном коммерческом опыте нужно рассказать отдельно: deployment/infra и исследование production incident, с личной ролью, гипотезами, причиной, исправлением и результатом.

GitHub repository отложен пользователем. Workflows/actionlint и локальный deployment не выдаются за remote runs. Отдельная Ubuntu VM, Ansible convergence и runner Online ещё впереди.
