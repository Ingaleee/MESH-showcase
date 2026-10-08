# MESH-showcase

Независимая копия Ruby backend и Next.js frontend для инженерной демонстрации. Основной продукт — соседний MESH. Здесь свои credentials, cookies, PostgreSQL, storage и Docker projects; исходники основного продукта этой работой не менялись.

## Начать показ

```powershell
npm run demo
```

Нужны Docker Desktop и Node.js 22/npm. Первая сборка требует registry access и памяти для ClamAV. Повторный запуск сохраняет secrets/data, применяет миграции, готовит synthetic accounts, проверяет реальный scanner, запускает partner/dashboard и выполняет CLI/browser сценарии. Новые browser reports/screenshots пишутся в отдельный .cache каталог; исторический evidence в Git не перезаписывается.

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

Current hosted CI: 131 Ruby examples в development и native Alpine runtime; 13/13 browser scenarios без skips/flaky; 52 OpenAPI operations; текущий release scan пяти exact digests — 0 HIGH/CRITICAL, включая unfixed, без CVE exceptions. Более ранний scan девяти образов остаётся историческим. Publishing прошёл bad package → validation → release → lost response → lookup → rollback с тремя remote POST, verified private bytes и тремя actual HTTP 200 signed callbacks.

[Текущий hosted Kubernetes](https://github.com/Ingaleee/MESH-showcase/actions/runs/37837294244) выполнил Terraform apply/drift/repair, migration ordering, Helm failed-rollout rollback, NetworkPolicy positive/negative controls и worker/DB recovery на Alpine registry digests. Scope — single-node K3s в ephemeral Ubuntu VM; старые local Debian results сохранены как исторические.

Сохраняются более ранние измерения 50k fanout, load lab и DB+files restore. Они не превращаются в новые замеры после каждой правки: даты и scope указаны в evidence.

## Что требует отдельного продолжения

GitHub verify, подписанный GHCR release, Ubuntu deploy/convergence/rollback/crash recovery и Kubernetes текущих registry digests успешно выполнены; [актуальные run IDs](docs/execution-status.md). Hosted VM существует только во время задания. Offsite/PITR, mixed-load capacity, длительное production SLO window и физическая HA не заявляются. Покупка VPS и постоянный self-hosted runner не требуются. Полные пределы приёмки — в [quality-bar.md](docs/quality-bar.md).

[Исторический transfer](docs/evidence/showcase-transfer.json), [separation](docs/evidence/showcase-separation.json), [новый evidence index](docs/evidence/publishing-implementation.json).
