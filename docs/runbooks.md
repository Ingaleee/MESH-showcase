# Эксплуатация MESH

Это инструкции для локального стенда и шаблон эксплуатационного процесса. Они не подтверждают SLA коммерческого deployment.

## Отложенные события

Признак: `mesh_outbox_oldest_seconds > 60`, delivery остаются pending/enqueued или есть failed. Посмотрите `docker compose logs --tail 100 dispatcher worker`; в операционном пульте найдите delivery и её класс последней ошибки. Проверьте, что queue DB доступна и pool подписан на массив `events, files, default`, а не на одну строку с запятыми.

После восстановления queue DB dispatcher возвращает stale claims в обработку. Событие с неподдерживаемой schema version исправляйте совместимым consumer; не редактируйте бизнес-историю. Повтор failed delivery выполняется кнопкой оператора и оставляет audit. Успешный replay должен сохранить прежнее количество notification effects для event/user.

Каждый enqueue получает claim_token; старый job после reclaim ничего не записывает. Ошибка старого enqueue также не сбрасывает новую попытку. Не очищайте token вручную: дождитесь lease или используйте операторский retry. Для rolling release сначала обновляются consumers и схема, затем dispatcher.

`mesh_queue_up=0` означает, что метрики queue DB не удалось прочитать; её counters при этом отсутствуют, а не равны нулю. `mesh_queue_ready{queue="events"}` и `mesh_queue_oldest_ready_seconds` показывают ожидание, `mesh_queue_claimed` — взятые jobs, `mesh_queue_scheduled` — отложенные, `mesh_queue_failed` — физически failed jobs Solid Queue. `mesh_queue_workers` учитывает Worker heartbeat моложе 90 секунд; это признак процесса, а не доказательство прогресса каждой задачи. Для application poison events отдельно смотрите `mesh_outbox_failed`: пустая очередь после restore не означает, что все durable intents успешны.

В [Prometheus](http://localhost:31090) сравните возраст ready jobs, workers и outbox. Если workers=0 — проверьте supervisor, connection budget и подписки. Если workers есть, а возраст растёт — проверьте зависшую работу, scanner/провайдер и saturation. Failed Solid Queue jobs сохраняйте до разбора; не включайте бесконечный retry poison events. Нужны правила retention и безопасной очистки failed history для длительной эксплуатации. `MeshMetricsUnavailable` также обнаруживает неуспешный scrape самого API: отсутствие метрики очереди нельзя считать здоровьем.

## Неопределённый платёж

Признак: `unknown`, просроченный `dispatching` или reconciliation exception. Сохраните operation ID, request/correlation ID и provider ID. Убедитесь, что lookup доступен. Не меняйте stable operation key и не отправляйте новую операцию из-за таймаута.

Обычный worker сначала делает lookup. Для дополнительной сверки нажмите «Сверить с провайдером» в операторском пульте; один вызов проверяет 25 наименее недавно проверенных операций. Старые requested тоже проверяются: это важно после восстановления backup. Сначала сравнивайте key, kind, provider ID, amount, currency и state; затем бухгалтерский эффект. Изменение проведённых записей запрещено, автоматические refunds отсутствуют.

Для остановки **новых отправок выплат** задайте `MESH_PAYOUTS_ENABLED=false` и пересоздайте worker. Эта настройка не отменяет уже отправленную операцию и не закрывает текущий запрос провайдеру. Расхождения подтверждённых результатов требуют разбирательства; разрешение exception допускается лишь после чистого lookup.

## Спор

До dispatch общий Settlement lock позволяет зафиксировать hold. После dispatch/unknown/confirmed попытка hold отклоняется: платёж мог уже уйти. Снятие hold выполняет оператор через `POST /api/v1/operations/settlements/{id}/release` с непустой причиной, текущим CSRF token и операторской сессией. Решение фиксируется в audit. Стенд не реализует возврат уже отправленной выплаты.

## Backup и restore

Для воспроизводимой проверки выполните `powershell -NoProfile -File scripts/restore-drill.ps1`. Скрипт останавливает собственный dispatcher, создаёт отдельный тестовый intent, делает custom-format `pg_dump` PostgreSQL 18, выполняет операцию провайдера, восстанавливает копию во временную `mesh_restore_<random>` и запускает reconciliation с отключёнными payouts. Он проверяет один provider POST, один восстановленный журнал и сохранённый immutable trigger. Временная DB удаляется по проверенному имени; исходная DB сохраняется. Dispatcher запускается в finally.

В реальном incident нужны отдельные backup object storage, encryption, retention, проверка файлов, credentials и очередь после восстановления. Демо drill не проверяет PITR, реплики, региональный отказ, восстановление S3 или заданные RPO/RTO. Нельзя просто поднять старую БД с включёнными payouts: сначала проверить внешний провайдер и reconcile.

Дополнительное упражнение `pwsh -NoProfile -File scripts/architecture-lab.ps1` восстанавливает большую отдельную DB **вместе с приватными файлами**. Оно останавливает только свои API/worker/dispatcher, делает custom dump и flat inventory blob keys, проверяет SHA-256, сохраняет completion manifest последним, восстанавливает DB и байты в пустые цели и запускает проверку. Недостающий файл и повреждение одного байта при прежнем размере должны быть обнаружены. Проверяются SQL-защита версии, её manifest и авторизованное скачивание. Queue DB намеренно новая: dispatcher должен восстановить enqueued outbox после lease с одним notification effect. [Границы и результаты](architecture-proofs.md).

При ручном восстановлении сначала изолируйте запись и выключите payouts, подтвердите полноту backup manifest, проверьте checksum dump и всех перечисленных файлов, загрузите primary/schema и storage, проверьте attachments/versions/доступ, восстановите queue, затем запустите recovery и reconciliation. Сохранённые пути файлов должны строиться из валидированных storage keys, а не из пользовательских имён или путей архива. Возвращать запись можно после проверок. Это упражнение не копирует gateway DB и не совмещает DB/files restore с внешним финансовым расхождением; финансовая recovery проверяется отдельным drill выше.

## Файлы

Недоступный scanner оставляет файл в карантине. Проверьте `scanner` и freshclam, затем `files` pool. Не устанавливайте available вручную ради скачивания. Файл, обнаруженный как infected, отклоняется. Публичные маршруты Active Storage выключены; скачивание разрешено только владельцу.

У scanner свой процесс Solid Queue. `scan_token` защищает запись результата, `scan_lease_until` восстанавливает смерть worker через 60 секунд, `scan_retry_at` задаёт durable backoff до 300 секунд. При `integrity_mismatch` сравните storage bytes с исходной загрузкой и SHA-256; новый файл передаётся новой версией. Непроверенные или rejected вложения не допускают приёмку результата. `mesh_files_oldest_seconds`, `mesh_files_quarantined` и `mesh_files_scan_errors` показывают задержки и сбои.

## Development API после аварии Docker

Showcase Compose запускает Rails с --pid /dev/null: жизненным циклом процесса управляет контейнер. Сохраняемый в bind mount server.pid после аварии может содержать 1 и блокировать следующий запуск. Проверка node scripts/check-api-restart.mjs ограничена showcase API: SIGKILL, start и ожидание реального session HTTP 200; она также включена в hosted CI. Это проверка одного процесса, не восстановление целого Docker host или пользовательских файлов. Production Rails имеет отдельную конфигурацию и этим изменением не меняется.

## Готовность API и ограничения входа

`/up` — liveness процесса, `/ready` — доступность primary PostgreSQL. При 503 на `/ready` проверьте DB, connection pool и сеть; ответ намеренно не раскрывает адрес или текст исключения. Отказ queue/scanner отслеживается отдельно. Не перезапускайте живой API только потому, что недоступна его БД.

При 429 входа/регистрации соблюдайте Retry-After. Budget общий для процессов и сохраняется в primary DB; очистка Rails cache или restart API не снимает лимит. Запросы session GET доступны отдельно. Dispatcher удаляет buckets старше суток ограниченными пачками; идентификаторы IP хранятся как HMAC со стабильным secret_key_base.

## Метрики и traces

Запускайте observability profile и `OTEL_TRACES_EXPORTER=otlp`. Prometheus target должен быть `up`; error 403 обычно означает, что internal hostname не разрешён Rails или token не совпадает. В Jaeger ищите `mesh-api`, request trace и `mesh.event.consume`. Trace context хранится в outbox и восстанавливается consumer. Showcase telemetry хранит историю Prometheus в named volume (7d/512MB), Alertmanager silences/notification log в named volume (120h), receiver — два файла до 8MB каждый. После restart активные alerts повторно присылает Prometheus. Это process-restart durability на одном host, не offsite monitoring.

## Изменение схемы и выпуск

Проверки выполняются workflow `.github/workflows/verify.yml`: контракт, границы, стиль, сборка, реальные SQL/race tests, security databases, Money types/mutations, TLC, браузер и restore drill. Remote verify имеет successful runs; ссылки и их revision находятся в execution-status.md. Hosted deploy принимает только успешный main release, подписанное происхождение и digests.

Для реального rolling release используйте expand/contract: сначала совместимые поля и reader, потом writer/backfill, затем ограничения и удаление старого пути. Здесь начальные миграции создают небольшую пустую схему; online migration большого production dataset и смешанные версии workers не проверялись. Миграционный owner и runtime role должны быть разными. Не переносите известные demo-пароли, tokens и широкую роль `mesh` в публичный deployment.

Поисковая миграция `20261008060000` проверена на 100 000 проектах: GIN индексы строятся concurrently вне DDL transaction с отдельным пятиминутным statement budget. Это не проверка rolling release под конкурентной production записью. После прерванного build проверьте `SELECT indexrelid::regclass, indisvalid FROM pg_index WHERE indexrelid IN (to_regclass('project_title_trigram'), to_regclass('project_description_trigram'));`. Invalid index удалите `DROP INDEX CONCURRENTLY <проверенное имя>` и повторите миграцию. `IF NOT EXISTS` сам по себе не подтверждает валидность; миграция отдельно проверяет её. Контролируйте свободный диск, WAL/IO и ожидающие транзакции. Rollback удаляет только эти индексы, сохраняя extension для других потребителей.

Production boot проверяет origin и отдельные секреты cookies/metrics/gateway/webhook. Runtime role template получает psql variables `runtime_role`, `database_name`, `migration_owner`; пароль задаётся отдельно. Сначала миграции от owner, затем выдача прав runtime. [Ревизия backend](backend-hardening.md) и `scripts/check-api-runtime.ps1` описывают проверенный non-root/read-only запуск. Для реальных файлов требуется отдельный writable storage volume.

## Interrupted Linux deployment

Use the exact accepted release checkout and the isolated state directory. Do not delete the OS lock or journal on the basis of age. A child Docker process may still own descriptor 9 after its parent dies; flock must decide ownership.

```bash
export MESH_DEPLOYMENT_STATE="$PWD/.cache/deployment"
bash scripts/release.sh deploy .cache/downloaded-release/release.json
```

The new owner reads the durable journal. If the preceding operation did not commit, it reapplies the last verified baseline and smoke-checks it before proceeding. Review current.json, previous.json, journal.json and the generated deployment report together with actual container image references. A failed rollback leaves a diagnostic failure; do not declare success merely because the original deploy failed. Preserve the report and repair the required dependency before rerunning the same wrapper. Database migrations are retained; destructive contract migrations require a separately planned release and recovery procedure.

Windows uses the conservative directory lock path and has a narrower recovery guarantee. The demonstrated inherited OS lock and SIGKILL recovery are Linux checks.

## Publishing snapshot and safe cleanup

```powershell
node scripts/check-publishing-continuity.mjs
docker compose exec -T api bin/rails publishing:uploads:reclaim
```

The restore exercise stops this showcase's API, worker and dispatcher, creates a primary and queue snapshot plus private-byte inventory, authenticates the encrypted archive before extraction, and restores into clean databases/files. Before restarting workers, unconfirmed restored Publishing operations become unknown and are looked up under the original operation ID. Never resolve uncertainty by sending a fresh publish command. The independent simulator may have advanced after backup.

Encryption keys stay separate from the archive in ignored local state. That separation is not independent disaster-safe key custody. This exercise does not replace an offsite backup or whole-VM recovery test.

Cleanup is a bounded dry-run unless APPLY=1. GRACE_DAYS must be at least two and must cover the explicitly supported backup recovery window. Active references, ordinary attachments and uploading leases are preserved; reclaimed tombstones cannot gain a new reference. A stale uploading intent uses its original key for recovery. This tool intentionally does not guess ownership of arbitrary legacy objects with no durable intent.
