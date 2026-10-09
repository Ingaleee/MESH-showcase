# MESH-showcase

Независимая копия Ruby backend и Next.js frontend для инженерной демонстрации. Основной продукт — соседний MESH. Здесь свои credentials, cookies, PostgreSQL, storage и Docker projects; исходники основного продукта этой работой не менялись.

## Начать показ

```powershell
npm run demo
```

Нужны Docker Desktop, Node.js 22/npm и Microsoft Edge на Windows. На Linux заранее установите Playwright Chromium и системные библиотеки: npm ci --ignore-scripts, затем npx playwright install --with-deps chromium. Первая сборка требует registry access и памяти для ClamAV. Повторный запуск сохраняет secrets/data, применяет миграции, готовит synthetic accounts, проверяет реальный scanner, запускает partner/dashboard и выполняет CLI/browser сценарии. Новые browser reports/screenshots пишутся в отдельный .cache каталог; исторический evidence в Git не перезаписывается.

[Publishing Lab](http://localhost:3200/publishing) · [MESH](http://localhost:3200/) · [Grafana](http://localhost:32092/d/mesh-reliability)

Synthetic operator: ops@mesh.local / MeshDemo2026!. Эти credentials относятся только к lab. Изображения/данные marketplace сохранены, Ruby — главный материал демонстрации.

```powershell
npm run demo:publishing
npm run demo:incident
```

[Сценарий на 15 минут](docs/interview-demo.md), [Publishing: код и гарантии](docs/publishing-lab.md), [фактические результаты](docs/execution-status.md), [security review](docs/security-review.md), [живой Kubernetes](docs/kubernetes-live-lab.md).

## Окружения

| Окружение                         | Вход                                                               | Изоляция                                                          |
| --------------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------- |
| Interview preview                 | localhost:3200, debug API:3201, finance gateway:3202, partner:3216 | mesh-showcase, synthetic accounts, private files                  |
| Telemetry                         | Prometheus:32091, Grafana:32092, Alertmanager:32093                | Loopback; authenticated internal receiver                         |
| Production demonstration          | HTTPS localhost:3243                                               | mesh-showcase-release; restricted DB role; immutable v2 inventory |
| GitHub verification configuration | localhost:3300–3303                                                | Unique job Compose project, fresh secrets                         |
| Architecture lab                  | API:3214, Prometheus:3215                                          | Separate logical DB/files with measured cleanup                   |
| Kubernetes exercise               | k3d-mesh-showcase                                                  | Dedicated DB/role/PVC, explicit kubeconfig; currently stopped     |

Production и Kubernetes не запускать одновременно с тяжёлым preview на тесном host. Остановка сохраняет volumes; данные не удаляются ради rollback. Development helper setup.ps1 остаётся доступен, для полного interview stand используйте npm run demo.

## Что подтверждено

Проверенный release `3d849af`: [CI](https://github.com/Ingaleee/MESH-showcase/actions/runs/37892418562) — 153/0 Ruby в development и 153/0 в native Alpine, 13 browser scenarios без skips/flaky; [подписанный GHCR release](https://github.com/Ingaleee/MESH-showcase/actions/runs/37892419510) — scan пяти exact digests, 0 HIGH/CRITICAL включая unfixed. [Ubuntu](https://github.com/Ingaleee/MESH-showcase/actions/runs/37898543604) подтвердил Ansible changed=0, mixed load, откат и восемь SIGKILL/recovery фаз. [Kubernetes](https://github.com/Ingaleee/MESH-showcase/actions/runs/37898550160) прошёл drift, CNI controls и rollout/rollback; [другая VM](https://github.com/Ingaleee/MESH-showcase/actions/runs/37898547328) восстановила primary/queue/private files и API/worker/dispatcher за 76.96s. Настоящий HTTP-партнёр подтвердил ротацию ключа и безопасное сохранение unknown: один POST и один внешний эффект. [Приёмка поддержки партнёра](docs/partner-support-acceptance-oct09.md) содержит исходные отчёты, hashes и границы. Предыдущая [reliability-приёмка f15af36](docs/reliability-acceptance-oct09.md) сохранена отдельно.

Для каждого отчёта указана точная ревизия, workload/fault configuration и окружение. Исторические 50k/fanout/DB+files результаты сохраняют прежнюю дату и scope; новый прогон не превращает их в новые измерения.

## Эксплуатационные границы

Hosted VM существует только во время задания. Подтверждены перегрузка admission и SQL contention в заявленном mixed profile, восемь deployment fault points с failed recovery, loss of source VM и независимое Windows backup/key custody. Не подтверждены online WAL/PITR, permanent backup retention, GitHub-provider failover, длинное production SLO окно, physical HA, большие concurrent uploads и весь возможный crash state space. Покупка VPS и постоянный self-hosted runner не требуются. Полные критерии и оставшиеся границы — [quality-bar.md](docs/quality-bar.md).

[Исторический transfer](docs/evidence/showcase-transfer.json), [separation](docs/evidence/showcase-separation.json), [новый evidence index](docs/evidence/publishing-implementation.json).

[Английское видео и 11 реальных экранов](https://ingaleee.github.io/MESH-showcase/), [подробный walkthrough](docs/visual-walkthrough.md) и [чистая подготовка Ubuntu](https://github.com/Ingaleee/MESH-showcase/actions/runs/37909616516): настоящий npm run demo, 17 stages, 4/4 browser, без owner-local .env/cache/data. Browser runtime/host libraries обозначены отдельно. Это отличается от старого локального single-scenario proof.
