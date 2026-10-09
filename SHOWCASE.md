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

Проверенный release `f15af36`: [CI](https://github.com/Ingaleee/MESH-showcase/actions/runs/37869060208) — 146/0 Ruby в development и 146/0 в native Alpine, 13 browser scenarios без skips/flaky; [подписанный GHCR release](https://github.com/Ingaleee/MESH-showcase/actions/runs/37869324980) — scan пяти exact digests, 0 HIGH/CRITICAL включая unfixed. [Ubuntu](https://github.com/Ingaleee/MESH-showcase/actions/runs/37872648042) прошёл mixed load, Ansible convergence и восемь SIGKILL/recovery фаз; [Kubernetes](https://github.com/Ingaleee/MESH-showcase/actions/runs/37870973532) — drift, CNI controls и rollout/rollback. [Другая VM](https://github.com/Ingaleee/MESH-showcase/actions/runs/37871090618) восстановила primary/queue/private files и возобновила API/worker/dispatcher, RTO 76.6s. Windows ciphertext/key custody проверена отдельно. [Приёмка четырёх reliability вопросов](docs/reliability-acceptance-oct09.md) содержит raw hashes, измерения, failures и границы.

Для каждого отчёта указана точная ревизия, workload/fault configuration и окружение. Исторические 50k/fanout/DB+files результаты сохраняют прежнюю дату и scope; новый прогон не превращает их в новые измерения.

## Эксплуатационные границы

Hosted VM существует только во время задания. Подтверждены перегрузка admission и SQL contention в заявленном mixed profile, восемь deployment fault points с failed recovery, loss of source VM и независимое Windows backup/key custody. Не подтверждены online WAL/PITR, permanent backup retention, GitHub-provider failover, длинное production SLO окно, physical HA, большие concurrent uploads и весь возможный crash state space. Покупка VPS и постоянный self-hosted runner не требуются. Полные критерии и оставшиеся границы — [quality-bar.md](docs/quality-bar.md).

[Исторический transfer](docs/evidence/showcase-transfer.json), [separation](docs/evidence/showcase-separation.json), [новый evidence index](docs/evidence/publishing-implementation.json).
