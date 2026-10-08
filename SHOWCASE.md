# MESH-showcase

Независимая копия Ruby backend и Next.js frontend для инженерной демонстрации. Основной продукт — соседний MESH. Здесь свои credentials, cookies, PostgreSQL, storage и Docker projects; исходники основного продукта этой работой не менялись.

## Начать показ

```powershell
npm run demo
```

Нужны Docker Desktop и Node.js 22/npm. Первая сборка требует registry access и памяти для ClamAV. Повторный запуск сохраняет secrets/data, применяет миграции, готовит synthetic accounts, проверяет реальный scanner, запускает partner/dashboard и выполняет CLI/browser сценарии.

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

118 Ruby examples в Debian development и native Alpine runtime; 13/13 полных browser scenarios; 51 OpenAPI operations; строгий scan девяти runtime images — 0 HIGH/CRITICAL, включая unfixed, без exceptions. Publishing прошёл bad package → validation → release → lost response → lookup → rollback с тремя remote POST, verified private bytes и тремя actual HTTP 200 signed callbacks.

Terraform real apply/drift/repair, Helm failed-rollout rollback, real NetworkPolicy deny и worker/DB recovery выполнены на single-node k3d. Kubernetes использовал предыдущие Debian application images; более поздние Alpine проверки имеют отдельный scope.

Сохраняются более ранние измерения 50k fanout, load lab и DB+files restore. Они не превращаются в новые замеры после каждой правки: даты и scope указаны в evidence.

## Что требует отдельного продолжения

GitHub repository пользователь отложил. Remote Actions/GHCR runs и runner Online ещё отсутствуют; конфигурация не называется выполненным pipeline. Ansible syntax проверен, convergence на Ubuntu VM не выполнен. Offsite/PITR, production SLO и физическая HA требуют другой среды/данных. Платные ресурсы и внешние сообщения не создавались.

[Исторический transfer](docs/evidence/showcase-transfer.json), [separation](docs/evidence/showcase-separation.json), [новый evidence index](docs/evidence/publishing-implementation.json).
