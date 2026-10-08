# Надёжность MESH: измерения и восстановление

Дата: 8 октября 2026. Это результаты выполненных локальных экспериментов и объяснение их границ. Основной MESH продолжает работать; лаборатория использует отдельные logical DB, контейнеры и storage volumes. PostgreSQL server и Docker host общие, поэтому изоляция данных не означает изоляцию ресурсов или аппаратных отказов.

## Воспроизведение

Нужны работающие Docker Desktop, PowerShell 7 (`pwsh`), Node.js 22 и локальные MESH db/scanner. Scanner должен принимать INSTREAM запросы. Запустите:

```powershell
docker compose --profile files up -d db scanner
pwsh -NoProfile -File scripts/architecture-lab.ps1
node scripts/check-architecture-evidence.mjs
```

Runner создаёт `mesh_lab_<12hex>` и queue/restore DB, два файловых тома и собственные API/worker/dispatcher/Prometheus. Порты 3214/3215 должны быть свободны. Default `All` очищает собственные ресурсы в `finally`; имена и Docker labels проверяются перед удалением. Dump и inventory остаются в игнорируемом `.cache/architecture-lab/<run>`; отчёты — в [evidence/showcase-architecture-lab](evidence/showcase-architecture-lab/README.md). Backup содержит синтетические данные и предназначен для локального упражнения; защищённое offsite хранение не настроено.

Для разбора есть стадии `Prepare`, `Seed`, `Measure`, `Exercise`, `Cleanup`. Они читают один локальный run.json; staged runs требуют явного Cleanup, а Prepare отказывается накладываться на активную лабораторию. Не прерывайте процесс аварийно, если рассчитываете на `finally`; после аварии выполните Cleanup. Runner не использует `--remove-orphans`, не останавливает основной dispatcher и не меняет его демонстрационные проекты.

## Что именно измеряется

Выборка: 100 000 synthetic projects, 20 000 creator profiles, 200 000 proposals, 20 001 accounts. Дополнительный проект проходит настоящие CreateProject → SubmitProposal → AwardProposal → SubmitWork и содержит два реальных файла, проверенных существующим ClamAV. Итоговые counts: 100 001 проект, 200 001 предложение и два blobs. У bulk rows нет полной искусственной business history; это данные для анализа чтения.

Измеряются лента, категория, substring search проекта/автора и глубокая cursor-страница за примерно 68 000 открытых проектов. По три warmup и 30 uncached ActiveRecord samples на случай. Сохраняются SQL, количество SELECT, ID выдачи и `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`. У всех пяти чтений два SELECT благодаря eager loading; это проверка этих read models, а не отсутствие N+1 во всём приложении. До/после должны возвращать одинаковые ID в одинаковом порядке.

Числа последнего успешного прогона находятся в [summary.json](evidence/showcase-architecture-lab/summary.json): `queryTimings`, `httpP95Ms`, `routeP95Ms`, `indexBytes`, `localRecoverySeconds`. Полные планы: [до](evidence/showcase-architecture-lab/queries-before.json) и [после](evidence/showcase-architecture-lab/queries-after.json). Маленькая выборка из 30 timings помогает диагностировать запрос; её p95 не является production SLO.

Обнаружены и исправлены два конкретных недостатка:

- Редкое слово в проекте заставляло читать большой brief text. Добавлены два GIN pg_trgm индекса по title/description; исходный `title OR description ILIKE` сохранён. На этой синтетической выборке медиана снизилась с 222,138 до 6,749 мс. Индексы занимают около 14 МБ; повторяющиеся synthetic descriptions сжимаются лучше реальных разнообразных текстов. Write latency, WAL и размер на реальных данных отдельно не измерены. Запросы без извлекаемых триграмм и популярные слова могут быть дорогими; [PostgreSQL описывает эту границу](https://www.postgresql.org/docs/18/pgtrgm.html).
- Cursor использовал `created_at < t OR (created_at = t AND id < id)`. Глубокий план посещал 11 848 shared buffers; после сравнения `(created_at, id) < (t, id)` — 6 buffers, медиана чтения 30,613 → 5,543 мс. Используется существующий составной B-tree. Before case явно сохраняет прежний predicate как контроль; after вызывает настоящий SearchProjects. Тесты проверяют timestamp ties, вставку нового проекта между страницами, привязку к actor/filter и подпись. Это не snapshot между страницами: изменения состояния старых проектов могут менять последующую выдачу.

Поиск авторов оставлен с прежней семантикой имени/headline/bio/skills. В плане остаются сканирования. Его улучшение потребует отдельного решения о search document и междоменных изменениях; два проекта GIN не объявляются оптимизацией каталога. 200 000 proposals распределены по проектам: fanout владельца к одному брифу измерен отдельно на 50 000 предложениях. Owner endpoint теперь использует bounded keyset pagination и server filters; история версий и комментариев также ограничена. [Отдельные bounds/benchmark](bounded-reads.md). Writes, preview/ZIP peak memory и финансовая нагрузка этими чтениями не подтверждены. Category median в этом прогоне выросла 6,827 → 8,365 ms; авторский search почти не изменился. Полная таблица сохранена, улучшение всех запросов не заявляется.

Далее запускается production API image: non-root, read-only root, снятые capabilities, 3 Puma threads, без OTEL export. k6 выполняет смешанное чтение пяти маршрутов 20 iterations/s × 120 секунд, с заранее выделенными 20 VUs и отдельным p95 threshold 500 ms для каждого маршрута. Deep cursor подписан тем же секретом, что production API. Прямой Docker HTTP не включает TLS, Caddy, Next.js/SSR и реальные пользовательские сессии. Это проверка заданного read budget на данном host, а не измерение предельной ёмкости. [Условия](evidence/showcase-architecture-lab/environment.json), [сырые метрики](evidence/showcase-architecture-lab/load.json).

## Реальные отказные сценарии

Без lab worker создаётся backlog из 50 durable events. Настоящий Prometheus снимает ready/claimed/failed/scheduled, возраст ready и heartbeat. Затем обычные worker и dispatcher запускаются, backlog обработан, у каждого события один notification effect, delayed alert исчезает. Повторяющиеся jobs допустимы; уникальный эффект защищён в primary transaction. Realtime broadcast остаётся подсказкой и может потеряться.

Отдельный producer подключается к закрытому PostgreSQL port queue URL: enqueue не получается, durable intent остаётся pending, retry time сохраняется, QueueMetrics сообщает unavailable. После возвращения нормального подключения обычный worker обрабатывает событие один раз. Общий PostgreSQL не останавливается: это реальная недоступность соединения конкретного producer, а не cluster failover.

Событие schema_version=999 проходит настоящий dispatcher/Solid Queue worker и после пяти ошибок переходит в failed; уведомлений нет. Prometheus видит application poison event. [Backlog/drain](evidence/showcase-architecture-lab/queue-drained.json), [outage](evidence/showcase-architecture-lab/queue-outage.json), [poison](evidence/showcase-architecture-lab/queue-poison.json), [временные ряды](evidence/showcase-architecture-lab/queue-timeline.json).

Lab alert rules используют ожидание >2 секунд и hold 3 секунды, чтобы упражнение было коротким; production rules используют 60 секунд/минутные окна. Это доказательство scrape/rule evaluation и перехода alert, без доставки Alertmanager/email/Slack внутри этой lab. Отдельное [incident exercise](sre-exercise.md) действительно доставило firing/resolved через Alertmanager в authenticated внутренний receiver; email/Slack не отправлялись. Prometheus distinction между pending и firing описан в [официальных правилах](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/). Heartbeat моложе 90 секунд не доказывает, что каждый worker делает полезную работу. Отсутствие scrape покрывает отдельный `MeshMetricsUnavailable`; отсутствующие queue counters не интерпретируются как ноль.

## Восстановление DB вместе с файлами

Порядок проверен настоящими инструментами:

1. Остановлены только lab API/worker/dispatcher; создан enqueued outbox claim, который уже не успеет обработаться. В primary сохраняется intent, а backup queue намеренно отсутствует.
2. Выполнен custom-format pg_dump, сохранены counts ключевых таблиц, inventory blob keys, размеры, Active Storage checksum и SHA-256 фактических байтов. Completion manifest записан последним; незавершённая директория не считается backup.
3. Dump загружен pg_restore в пустую restore DB, перечисленные байты скопированы в новый storage volume. Проверены все перечисленные metadata/counts и blobs, состав attachments, version manifest и неизменяемость submission через прямой SQL update.
4. Удаление файла обнаружено. Затем один байт изменён **при прежнем размере**: SHA-256 обнаружил повреждение. В обоих случаях восстановлены только байты тестовой копии; исходные файлы не затронуты.
5. Реальная Rails integration HTTP-сессия проходит cookie sign-in/CSRF и скачивает оба приватных файла; их SHA-256 совпадает с исходной загрузкой, `Cache-Control: private, no-store` сохранён. Это controller/auth проверка восстановленной копии, без TLS proxy.
6. Запущены обычные worker/dispatcher с пустой queue DB и выключенными payouts. Старый enqueued claim recovered после lease, создан ровно один notification effect.

Dump size, file bytes и elapsed сохранены в [backup](evidence/showcase-architecture-lab/backup.json), [restore checks](evidence/showcase-architecture-lab/restore-verified.json), [queue recovery](evidence/showcase-architecture-lab/restored-queue.json) и [recovery time](evidence/showcase-architecture-lab/recovery-time.json). Timer включает backup, restore, проверки доступа, boot workers и lease recovery. Это один local elapsed, а не договорённый production RTO. RPO в упражнении относится к остановленной записи на границе snapshot; WAL/PITR и online согласованность не проверены.

pg_dump даёт consistent snapshot одной DB, но не копирует внешние файлы; [официальная документация](https://www.postgresql.org/docs/18/app-pgdump.html). Для текущего disk storage выбран понятный quiescent protocol. Нужны собственные retention/encryption/offsite политики и versioned object storage, чтобы убрать паузу и поддержать другие failure models. Hash manifest не является подписью доверенного внешнего хранилища. SHA-256 не пересчитывается на каждом обычном download; проверки при загрузке/сканировании и restore не гарантируют неизменность writable storage между ними.

Queue rebuild покрывает outbox intents. Scanner и finance имеют свои durable fields/recovery, проверенные отдельными тестами, но потерю произвольного Active Job без источника в primary нельзя считать восстановленной. Gateway DB здесь не копируется; reconciliation внешних денег проверяется отдельным [финансовым упражнением](evidence/restore-drill.json), без утверждения единого DB/files/provider incident.

## Гарантии, стоимость и границы

| Гарантия | Что её обеспечивает / проверяет | Цена | Граница |
|---|---|---|---|
| Одна выбранная договорённость | Lock, transaction, unique/FK/check constraints; concurrent SQL tests | Сериализация одного проекта | Не гарантирует отсутствие ожидания locks |
| Повтор команды не создаёт новый результат | Idempotency и business effect в одной primary transaction | Rows/storage, stable request key | Внешняя система требует своего протокола повторов |
| История версий и terms не меняется | DB triggers/FKs, manifest; SQL restore probe | Дополнительная модель/хранение истории | Не юридическая подпись, не immutable hardware storage |
| Durable event не теряется при failed enqueue | Primary outbox, leases/tokens, dispatcher; live queue exercise | Polling, дополнительные writes, задержка | At-least-once jobs; нельзя обещать exactly-once сеть |
| Один notification effect на event/account | Unique key и effect+processed в transaction | DB contention/индекс | Websocket доставка best effort |
| Poison event не повторяется бесконечно | Durable failure budget 5; live failed state + alert | Операторское исправление/replay | Требуется retention физической queue history |
| Непроверенный файл не принимается | Quarantine, checksum/SHA, scanner claim, acceptance locks/tests | Scan/IO и ожидание | Scanner не является доказательством отсутствия всех угроз |
| Backup достаточен для выбранного DB/files сценария | Quiescence, dump+inventory, hashes, restore/download probes | Пауза writers, копия storage, время проверки | Не PITR/S3/region failover и не доказанный production RPO |
| Отказ очереди виден | Up/heartbeat/age/state gauges, scrape alert | Дополнительные bounded-time SQL reads | Большой backlog может исчерпать metric query timeout; доставку проверяет отдельный local incident, внешнего on-call канала нет |
| Поиск укладывается в проверенный read budget | SQL/BUFFERS + k6 на заданных данных | GIN disk/write upkeep и операционная миграция | Только выбранные запросы, synthetic distribution и local host |

Такой backend можно объяснять через конкретные переходы, эксперименты и ограничения. Следующие решения следует принимать по изменившемуся инварианту или измеренному bottleneck; наличие модной инфраструктуры само по себе не добавляет гарантий.
