# Демонстрация MESH-showcase за 15 минут

Перед собеседованием из MESH-showcase выполните npm run demo. Откройте [Publishing](http://localhost:3200/publishing), [Grafana](http://localhost:32092/d/mesh-reliability), [каталог evidence](execution-status.md). Не стройте образы и большой dataset впервые перед интервьюером. Команда подготовки сохраняет данные; новые упражнения создают synthetic records.

| Время     | Демонстрация                                                                      | Главный инженерный аргумент                                                                              |
| --------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 0–2 min   | Бриф → предложение → выбор автора → версия → приёмка                              | Ruby transaction, authorization, fixed agreement terms и ограничения БД                                  |
| 2–4 min   | 50k Publishing history, scoped cursor и query plans                               | 30 materialized rows; index убирает сортировку почти 50k; tenant selectivity имеет цену                  |
| 4–7 min   | Publishing: defective ZIP → error code → исправленный кандидат → release          | Проверяются конкретные bytes/digest под конкретной policy/config, не абстрактное имя версии              |
| 7–10 min  | Потерянный ответ → unknown → ротация ключа → diagnostic → lookup → confirmed      | Неопределённость после I/O; нельзя повторить POST только из-за timeout; партнёр хранит operation ID      |
| 10–12 min | Остановить worker, смотреть очередь/HTTP/alert, восстановить                      | HTTP health отдельно от полезной работы; durable effects и replay без дублей                             |
| 12–14 min | Exact image scan, HTTPS release/rollback, Kubernetes drift/deny/recovery evidence | Digest chain, роль миграций, image rollback отдельно от DB; различие readiness и liveness                |
| 14–15 min | DB+private-files recovery и tradeoffs                                             | Fresh VM + mesh_runtime + notification, independent ciphertext/key custody; RPO barrier и HA/PITR limits |

Worker exercise запускается npm run demo:incident и обычно укладывается в 1–2 минуты на этом host. Если timing изменился, показывайте сохранённый report с реальными timestamps, а не обещайте гарантированное время.

CLI drill npm run demo:publishing печатает operation IDs и diagnostic JSON. Для ручного просмотра — команды [Publishing lab](publishing-lab.md). Полные подписи/credential bytes не демонстрируются. Synthetic operator: ops@mesh.local / MeshDemo2026!.

## Что открыть в Ruby

RequestDeployment показывает короткую transaction и idempotency; Publishing::Application::ProcessDeployment — независимый workflow, Domain::DeploymentRules — lease/identity/fencing, Infrastructure::DeploymentStore/Partner/Artifacts — механизмы; Publishing::Composition связывает реализации. Legacy ProcessDeployment facade сохраняет API/job compatibility; I/O выполняется вне lock/transaction; ApplyObservation — связывание remote identity, bytes и sequence; ReceiveCallback — подпись, replay и monotonic state. Затем показать SQL triggers/composite FK и настоящий regression test. Steep сейчас проверяет Money boundary, не весь backend.

Объясните компромиссы: modular monolith упрощает согласованность; durable polling подходит этому объёму, но имеет стоимость; 2 MB ZIP ограничивает нагрузку и хранится через private Active Storage, большие artifacts требуют другой storage стратегии; reconciliation возможен только при соответствующем partner contract; Alpine принят после native suite, не ради меньшего размера; local Kubernetes не доказывает HA.

[RU postmortem и EN partner update](publishing-reliability.md) — synthetic exercises. Две истории о вашем реальном коммерческом опыте нужно рассказать отдельно: deployment/infra и исследование production incident, с личной ролью, гипотезами, причиной, исправлением и результатом.

GitHub repository опубликован; verify и GHCR release имеют реальные successful runs. Для интервью открыть actual runs/artifacts из execution-status.md. Hosted Ubuntu — временная VM задания, не постоянно доступный production сервер. Actual Ubuntu convergence, rollout/rollback и crash recovery подтверждаются отдельными reports; ссылки должны указывать на принятый release. Для показа подготовить стенд заранее, а затем открыть сохранённые workflow artifacts: полная холодная сборка в 15 минут не входит.

[Current mixed load / eight crash phases / fresh VM / user deadline evidence](reliability-acceptance-oct09.md) открывать заранее. Не пытайтесь выполнить холодный release/restore впервые за 15 минут; покажите сохранённые exact-run reports и объясните стоимость гарантий.

Перед показом выполните `npm run test:partner-support:evidence`. [Новая приёмка](partner-support-acceptance-oct09.md) связывает HTTP-ротацию, безопасную диагностику, 153+153 Ruby, browser, Ubuntu, Kubernetes и fresh-VM restore с одним release. `npm run demo:partner-support` — отдельное упражнение на disposable peer; оно не меняет ключ существующего simulator.

[Английское видео и 11 реальных экранов](https://ingaleee.github.io/MESH-showcase/), [подробный walkthrough](visual-walkthrough.md) и [чистая подготовка Ubuntu](https://github.com/Ingaleee/MESH-showcase/actions/runs/37909616516): настоящий npm run demo, 17 stages, 4/4 browser, без owner-local .env/cache/data. Browser runtime/host libraries обозначены отдельно. Это отличается от старого локального single-scenario proof.
