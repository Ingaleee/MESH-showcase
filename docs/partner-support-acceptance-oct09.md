# Приёмка поддержки внешнего партнёра · 9 октября 2026

Принята application revision `3d849af84c9afd8885f57ae7f6390c2d540361e4`. Каждый инфраструктурный workflow checkout-ит именно этот release commit и проверяет подписанное происхождение его образов. Последующие documentation/evidence commits не объявляются новым application release.

| Проверка | Фактический результат | GitHub run |
| --- | --- | --- |
| Полный CI | 153 development + 153 native Alpine Ruby, 0 failures/pending; 13 browser, 0 skipped/flaky; реальный partner/scanner, telemetry, worker incident и restore | [37892418562](https://github.com/Ingaleee/MESH-showcase/actions/runs/37892418562) |
| GHCR release | Четыре подписанных образа и pinned upstream Caddy; пять exact digest scans, 0 HIGH/CRITICAL включая unfixed | [37892419510](https://github.com/Ingaleee/MESH-showcase/actions/runs/37892419510) |
| Ubuntu | Ansible second apply changed=0, TLS/mixed load, direct SQL denies, rejected runtime rollback, восемь SIGKILL фаз и failed recovery | [37898543604](https://github.com/Ingaleee/MESH-showcase/actions/runs/37898543604) |
| Другая VM | 38 primary / 15 queue tables, 2 private objects / 394 bytes; authenticated runtime, worker, callbacks, unknown lookup; независимые Windows ciphertext/key custody | [37898547328](https://github.com/Ingaleee/MESH-showcase/actions/runs/37898547328) |
| Kubernetes | Terraform drift repair, migration ordering, реальные CNI positive/negative controls, worker once-only, readiness/liveness, rollout и rejected upgrade rollback | [37898550160](https://github.com/Ingaleee/MESH-showcase/actions/runs/37898550160) |

## Исправленные риски поддержки

При отсутствии ключа диагностика и каталог раньше выдавали 503, скрывая сохранённую историю. Read models теперь возвращают локальное состояние, nullable input compatibility и стабильный configuration error; команды validation/publication закрыты до восстановления конфигурации. Некорректная кодировка ключа тоже отклоняется до HTTP I/O.

401/403 теперь дают PARTNER_AUTH_REJECTED вместо общего transport error. Начатая операция сохраняет unknown и исходный ID. Действие restore_configuration указывает восстановить approved credential, затем возобновить ту же операцию. Для недоступного peer и 404 результат остаётся unknown с lookup_only; отсутствие ответа не разрешает повторный POST. Активная lease требует ожидания, завершённая failure не получает инструкцию resume.

Диагностика только читает локальную историю. Она не обращается к партнёру и явно возвращает remote_state_queried=false. Factual EN update включает operation/digest/correlation и безопасный следующий шаг; его проверяет и отправляет оператор. Автоматической внешней переписки нет.

## Реальное упражнение

`npm run demo:partner-support` использует disposable non-root Node/SQLite HTTP peer и test DB. Сначала peer фиксирует выпуск и теряет ответ. Затем его процесс заменяется с новым ключом и тем же private volume: старый credential получает реальный HTTP 401, новый проходит контракт. Начатая операция подтверждается lookup, устаревшая validation блокирует новый выпуск, старая worker claim не может переписать новый результат.

Missing credential, unavailable peer и 404 отдельно проверяют сохранение ID/unknown и read-only diagnostic. Итог всего упражнения — один POST и один внешний эффект. Callback HMAC rotation/replay проверяется через настоящий Rails Rack endpoint; доставка callback по сети в этом упражнении не заявляется. Отдельное обычное Publishing demo в CI проверяет реальные сетевые callbacks. Lease fencing здесь использует контролируемое истечение времени и реальные DB claims; deployment SIGKILL подтверждается другим Ubuntu упражнением.

## Измерения текущего окружения

TLS read profile: 300 запросов, 0 ошибок, p95 91.61ms. Mixed profile: baseline 5 arrivals/s, 150 запросов, p95 98.55ms; далее admission overload и SQL lock contention. 937 business commands дали 937 notification effects, без duplicate events/effects и pending backlog. Эти значения относятся к указанному hosted VM/profile, не являются обещанием production SLA или ресурсного предела.

Fresh-VM RTO 76.96s включает checkout/image acquisition и возобновление runtime в этом упражнении; цель заранее 900s. RPO=0 только на quiescent snapshot barrier. Состояние партнёра опережает application backup; reconciliation не создала второй POST.

## Доказательства и отрицательные проверки

[Каталог raw reports](evidence/partner-support-oct09/ci/manifest.json) сохраняет байты артефактов, source SHA, GitHub run, downloaded ZIP digest и per-file SHA-256. Для каждого environment есть отдельный manifest. `npm run test:partner-support:evidence` сверяет chain, hashes, exact source восьми файлов, безопасные action codes, one-effect outcome и инфраструктурные результаты. Исторический f15af36 каталог сохранён без подмены ревизии. [Четыре отрицательных контроля evidence gate](evidence/partner-support-oct09/evidence-controls.json) отклоняют повреждённые байты, повторный POST, unsafe next action и несовпадение source hash, включая semantic tampering с пересчитанным report hash.

[Неудачный browser run](https://github.com/Ingaleee/MESH-showcase/actions/runs/37890030765) и [raw geometry](evidence/partner-support-oct09/failed-browser/layouts.json) сохранены: непрерывный SHA-256 текст вызывал overflow. Исправлена CSS wrapping, width threshold не ослаблен. Новая полная compiled UI прошла 1440/1024/390px и accessibility; [scoped local CSS negative/positive control](evidence/partner-support-oct09/failed-browser/css-control.json) обозначен как отдельный эксперимент на прежнем preview, а не полный E2E. [Локальный actual current-image Publishing browser scenario](evidence/partner-support-oct09/local-preview/manifest.json) также прошёл после обновления preview; его scope — существующие showcase данные, не cold-clone setup.

## Границы и готовность к интервью

Это законченная техническая демонстрация цикла внешней интеграции и её эксплуатации в заявленной модели отказов. [Vacancy mapping](vacancy-readiness.md), [EN partner guide](partner-support.md), [15-minute walkthrough](interview-demo.md) и [Clean Architecture scope](clean-architecture.md) связывают поведение с Ruby кодом и компромиссами.

Ротация использует переключение одного approved credential, без zero-downtime keyring. Нет physical HA, multi-node PVC, provider-wide failover, online WAL/PITR, permanent backup retention, длительного production SLO или независимого pentest. Kubernetes lab не выполняет partner/scanner workload. Малая recovery fixture доказывает согласованность и resume, не throughput большого восстановления. Коммерческий опыт, личные incident stories и устный английский подтверждает кандидат.
