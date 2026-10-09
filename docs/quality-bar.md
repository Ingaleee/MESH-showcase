# MESH-showcase: проверяемые критерии готовности

Аудит: 8 октября 2026. Проверенная ревизия: `0034674741db8a7ea6a6a9ac18238f1ba8af47d1`.

Это план приёмки существующих Ruby/backend, marketplace, Publishing и инфраструктуры. Новые проверки ниже ещё не выполнены. В этом аудите прочитаны ключевые use cases, SQL constraints/triggers, HTTP/ZIP boundaries, API/UI Publishing, deploy/CI/IaC и имеющиеся reports; актуальный статус Actions получен через GitHub API. Новые SQL-пробы, нагрузка, restore и rollout в ходе аудита не запускались.

## Прогресс после исходного аудита

Аудит ниже относится к исходной ревизии 0034674 и сохраняется как основание работ. Его фраза «не выполнено» описывает состояние на начало аудита. Новые фактические результаты находятся в [acceptance-oct08.md](acceptance-oct08.md), [partner-support-acceptance-oct09.md](partner-support-acceptance-oct09.md) и [execution-status.md](execution-status.md).

| Критерий | Реализованное и проверенное                                                                                                                    | Остаток полного критерия                                                                                |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Q01      | Current hosted clean preparation, 153/0 Ruby and 153/0 native, 13 browser; security/partner/recovery                                           | Exact reports and artifact/source hashes recorded in reliability acceptance; no independent audit claim |
| Q02      | NULL-safe confirmed fields, active/rollback guards, direct SQL negatives                                                                       | Runtime-role SQL probe прошёл в run 37837289487                                                         |
| Q03      | Durable upload intent, I/O вне transaction, bounded reclaim и SQL reference guards                                                             | Произвольные legacy objects без intent не очищаются; общий destructive GC не заявлен                    |
| Q04      | Inherited flock/fsync journal; eight actual SIGKILL phases, killed recovery, unavailable engine and corrupt journal denial                     | No kernel/power-loss or complete interleaving matrix; damaged metadata needs manual investigation       |
| Q05      | Threat model, ownership/HMAC/HTTP/ZIP tests, history scan, exact-image scan, signed source verification                                        | Real HTTP rotation/outage drill accepted at 3d849af; independent adversarial review not performed                       |
| Q06      | Signed scoped cursor, ties/insertion/page tests, active отдельно от history, API types                                                         | Проверен declared API/read scope                                                                        |
| Q07      | Real partner timeout/lookup/rollback, credential rotation, 401/404/outage, callbacks, fencing и safe diagnostic                                                                          | Полная interleaving/property crash matrix шире выполненного real drill                                  |
| Q08      | Registry release, A→B→old runtime on new schema, failed image rollback                                                                         | Migration locks на большом dataset и все старые Publishing job payloads не профилированы                |
| Q09      | 50k SQL; current 10k mixed TLS reads/commands/replays, open arrivals, admission overload + SQL contention, resources                           | Declared profile accepted; no machine CPU/RAM ceiling, long soak or large concurrent uploads claim      |
| Q10      | Mature denominator includes failed/unfinished; user deadline alert firing/resolved, 50 once-only effects; durable restart                      | Initial 99% lab objectives are not measured 30-day production SLO                                       |
| Q11      | Separate source/target VM UUIDs, authenticated primary/queue/private restore; resumed mesh_runtime API/workers; Windows key/ciphertext custody | Quiescent RPO only; no online WAL/PITR, permanent retention or provider-wide failover                   |
| Q12      | Current signed registry digests: Ansible changed=0, Terraform drift/repair, CNI positive/negative and Helm rollout/rollback                    | Single-node ephemeral K3s; no physical HA or multi-node shared PVC guarantee                            |
| Q13      | Packwerk/contracts/Money; Rails-free Publishing Domain/Application + ports/adapters and dependency negative control                            | Other modules retain Rails coupling; whole-backend Steep/mutation/strict Clean Architecture not claimed |
| Q14      | RU/EN сценарий, source/run/hash evidence, failed attempts сохранены                                                                            | Личная репетиция и реальные коммерческие истории кандидата требуют его участия                          |

Эта матрица намеренно не объявляет все Q01–Q14 принятыми. Завершение семи ближайших шагов делает showcase пригодным для инженерного разбора, но не превращает его в доказанную production систему без эксплуатационных границ.

## Дополнительная приёмка 9 октября

[Текущий reliability record](reliability-acceptance-oct09.md) закрывает четыре выбранных пробела: declared mixed overload, расширенные deployment crash/failed-recovery переходы, другая VM + independent key/backup custody и user-outcome SLIs. Q04/Q09/Q10/Q11/Q13 выше обновлены по фактическим outcomes. Остальные пределы сохраняются; личные коммерческие истории и репетиция кандидата не могут быть заменены generated code/report.

## Значение оценки

«10/10» здесь означает, что все обязательные критерии ниже приняты для зафиксированной ревизии, окружения, модели отказов и нагрузки. Наличие критического незавершённого критерия исключает такую оценку: результаты не усредняются. Это оценка готовности showcase к техническому разбору, с документированными эксплуатационными пределами.

Для каждой гарантии нужен набор: требование → реализация Ruby/SQL → проверка с отрицательным сценарием → свежий результат → стоимость и граница гарантии. Количество технологий, строк, тестов и процент покрытия сами по себе не являются критериями приёмки.

P0 — блокирующая корректность/безопасность/воспроизводимость. P1 — обязательная эксплуатационная и демонстрационная готовность. В финальный acceptance входят оба уровня.

## Что действительно есть

Локальные reports подтверждают 118/0 RSpec в development и native Alpine, полный browser run 13/13, защищённый HTTP, immutable Publishing inputs, idempotency, fenced claims, подписанные callbacks и reconciliation после потерянного ответа. Есть local scan девяти images, rollback exercise, live Kubernetes/NetworkPolicy/drift exercises и более раннее восстановление DB+files.

Первый настоящий [GitHub run](https://github.com/Ingaleee/MESH-showcase/actions/runs/37811605035) завершился failure: infrastructure Shellcheck SC2034; backend 118 examples / 2 failures из-за фиксированного имени session cookie в тестах. Артефакт mesh-evidence существует. Последующие шаги этого job не считаются выполненными.

Исторические зелёные отчёты имеют собственные даты и scope. Они не становятся результатами текущего GitHub run. Kubernetes проверял предыдущие Debian application images; старый restore выполнен до Publishing.

## Найденные конкретные пробелы

| Наблюдение                                          | Основание                                                                                                                                                                   | Последствие и статус                                                                                                                                                                             |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Тесты фиксируют cookie name                         | [session_reads_spec.rb](../apps/api/spec/requests/session_reads_spec.rb), [session initializer](../apps/api/config/initializers/session.rb)                                 | Runtime корректно использует отдельное CI-имя, тест падает; подтверждено remote run                                                                                                              |
| Conditional CHECK не исключает NULL sequence        | [BindPublishingProvenance](../apps/api/db/migrate/20261008142000_bind_publishing_provenance.rb)                                                                             | Для confirmed с заполненными remote_id/confirmed_at и NULL remote_sequence выражение CHECK становится NULL; статически выявленный пробел, нужна regression SQL-проба                             |
| Active pointer можно очистить                       | [CreatePublishing trigger](../apps/api/db/migrate/20261008140000_create_publishing.rb)                                                                                      | Проверка binding выполняется только при непустом новом pointer; очистка при прежнем positive sequence отдельно не запрещена. Семантику initial/active состояния нужно явно закрепить и проверить |
| Upload находится внутри SQL transaction             | [SubmitCandidate](../apps/api/packs/publishing/app/services/publishing/submit_candidate.rb), [Idempotency](../apps/api/packs/platform/app/services/platform/idempotency.rb) | Storage I/O удерживает transaction и idempotency lock; SQL rollback не откатывает записанные bytes. Есть crash/latency boundary                                                                  |
| Нет завершённого lifecycle артефактов               | [Candidate](../apps/api/packs/publishing/app/models/publishing/candidate.rb) хранит прямой artifact_blob_id                                                                 | Нужна очистка object без DB row и blob без владельца с защитой active/pending/backup references                                                                                                  |
| Publishing history обрезана                         | [controller](../apps/api/app/controllers/api/v1/publishing_controller.rb)                                                                                                   | Partners limit20, candidates/deployments limit30 без cursor. Старые записи недоступны через list                                                                                                 |
| Active release вычисляется из последних deployments | [Publishing UI](../apps/web/src/app/publishing/page.tsx)                                                                                                                    | При более чем 30 более новых intent старый действующий release может отсутствовать в отображаемом списке; нужен отдельный scoped active read                                                     |
| Deploy state не защищён от остановки процесса       | [release.mjs](../scripts/release.mjs)                                                                                                                                       | mkdir lock и прямой writeFile current/previous; SIGKILL не выполняет finally. Возможны stale lock/частичная запись. Это пока не воспроизведённая fault-гипотеза                                  |
| Public repository не проходит deploy guard          | [deploy workflow](../.github/workflows/deploy.yml)                                                                                                                          | private-only guard заблокирует нынешний public repo; механизм доверия нужно спроектировать до подключения runner                                                                                 |
| История observability временная                     | [SRE Compose](../infra/sre/compose.yaml)                                                                                                                                    | Prometheus TSDB, Alertmanager state и receiver receipts на tmpfs; данные не рассчитаны на сохранение после пересоздания                                                                          |
| Документация отстаёт от факта                       | SHOWCASE/execution-status/interview-focus                                                                                                                                   | Repo всё ещё описан как отложенный, remote runs — как отсутствующие; нужен новый truthful status                                                                                                 |
| Evidence checker читает конкретные прошлые reports  | [check-publishing-evidence.mjs](../scripts/check-publishing-evidence.mjs)                                                                                                   | Проверка согласованности архива не заменяет свежую проверку выбранной ревизии                                                                                                                    |

PostgreSQL принимает CHECK, который вычисляется в TRUE или NULL; условное обязательное поле требует явного исключения NULL. [Официальная документация](https://www.postgresql.org/docs/18/ddl-constraints.html).

## Q01 — Воспроизводимый CI · P0

Исправить cookie expectations через фактическую настройку приложения, сохранив сценарий GET → login/logout без перезаписи поздней session cookie. Исправить SC2034 без выключения Shellcheck. Довести настоящий hosted Linux pipeline через все существующие проверки, native runtime, real partner, browser и restore.

Приёмка: fresh environment из clone, отсутствие незаявленных зависимостей от Windows/.cache/.env; zero failures и zero skipped critical scenarios; все предусмотренные jobs выполнены. Минимум cold preparation и повторный запуск на исправленной ревизии после обнаруженных portability/startup проблем. Считать обнаруженные tests динамически; объяснять каждое допустимое исключение, не фиксировать число 118 как вечный quality gate. Полные sanitized reports сохраняются и при отказе.

Доказательства: run URL, SHA, environment context, test/scan/browser reports и проверка их содержимого после скачивания.

## Q02 — Инварианты непосредственно в БД · P0

Уточнить conditional confirmed fields, initial/active partner state, принадлежность deployment/validation/candidate/partner, монотонность sequence, rollback basis и terminal immutability. Внешнюю истинность callback обеспечивает приложение/контракт; БД защищает структуру и согласованность сохранённого состояния.

Приёмка: прямые INSERT/UPDATE/DELETE вне ActiveRecord validations отвергают запрещённые состояния, включая NULL, чужой partner, некорректную active reference и изменение terminal history. Положительные сценарии проходят. SQL-пробы идут на disposable DB под реальной runtime role и отдельно проверяют миграционные привилегии. Для параллельных writers использовать независимые connections/processes, bounded waits и проверку конечного состояния, а не sleep как доказательство.

Доказательства: invariant matrix, raw SQL regression tests, concurrent reports; корректный backup/restore сохраняет ограничения.

## Q03 — Артефакты, транзакции и очистка · P0

Спроектировать upload intent/finalization так, чтобы тяжёлый storage I/O не удерживал бизнес-транзакцию и idempotency lock. Сохранить single logical candidate при concurrent/repeated request, fingerprint conflict и привязку конкретных bytes. Durable intent должен позволять найти незавершённый upload после аварии.

Очистка должна различать: object без DB row; unreferenced blob; referenced blob с missing/corrupt bytes. Учитывать прямой candidate FK, обычные attachments, незавершённый upload, выполняющуюся операцию и backup retention. Нельзя определять «не нужен» только через ActiveStorage::Blob.unattached: Publishing использует собственную связь.

Приёмка: faults до upload, после upload/до commit, после commit/до response; проигравший concurrent запрос не удаляет победивший artifact. Cleanup имеет dry-run, bounded batches, повторную проверку ownership перед удалением и audit. Удаляет только допустимые старые orphan objects; active/leased/retained объекты остаются. При недоступном storage операция завершается в известном bounded состоянии.

Доказательства: crash matrix, private download/SHA proof, before/after inventory, cleanup negative cases и объяснение reclaim grace period.

## Q04 — Восстановление самого deploy · P0

Добавить durable журнал фаз deployment, атомарное обновление metadata и понятное exclusive ownership. Восстановление stale lock должно доказывать, что прежний deploy больше не владеет выполнением; TTL сам по себе не разрешает параллельный выпуск. Сверять журнал с фактическими containers/images/schema перед продолжением.

Приёмка: принудительно остановить deploy после lock, миграции, частичного rollout, smoke и перед записью state. Следующий запуск либо безопасно завершает/откатывает, либо явно останавливается с диагностикой. Current/previous не становятся повреждённым JSON. Два deploy не выполняются одновременно. При failed rollback отдельно фиксируется деградация, исходная причина и следующие действия.

Доказательства: fault reports по фазам, actual images, preserved business/files data, concurrent deployment rejection и operator recovery runbook.

## Q05 — Границы доверия и security · P0

Составить компактный threat model: browser/CSRF/session, operator ownership, callback/HMAC/replay, ZIP/digest/storage, outbound HTTP, registry/provenance, runner/VM и backup keys. Использовать существующие защиты, добавляя проверки найденных дыр.

Для public portfolio предпочтительный план: hosted CI и deploy на отдельную VM через ограниченный канал из доверенного workflow. Постоянный self-hosted runner в public repo не считать безопасным просто из-за manual trigger/environment. Если self-hosted необходим, нужен отдельный подтверждённый контур доверия и чистое исполнение с одним job; его выбор оформляется ADR. PR из forks не получают deployment access. Repo visibility автоматически не меняется.

Приёмка: two-owner/operator access matrix, forbidden private download/diagnose/reconcile, real CSRF boundary, HMAC raw bytes/replay/expiry, ZIP bombs/duplicates/traversal/budget, TLS/redirect/response/deadline checks. Проверить rotation credentials и последующее reconciliation старых unknown операций. Повторить secret scan по Git history и sanitization новых logs/artifacts. Scan exact deployment digests; exceptions требуют применимости, owner и срока пересмотра.

Доказательства: threat matrix, negative tests, rotation drill, narrow token/SSH/DB permissions, current scans и доверенная provenance verification.

Риски публичного self-hosted runner и ограничения environment approvals описаны в [GitHub security reference](https://docs.github.com/en/actions/reference/security/secure-use).

## Q06 — История, active read и frontend contract · P1

Добавить cursor pagination с полным deterministic order, scope к владельцу и пределом page size для Publishing partners/candidates/deployments. Active state загружать независимо от history window. Счётчики должны иметь явную семантику: текущая страница или все relevant records.

Приёмка: 50k historical rows, одинаковые timestamps, вставки между чтениями, переход по страницам без overlap и недоступных gaps в выбранной cursor semantics. Active deployment старше 30 последних intent остаётся видимым. Query/materialization/memory bounded page size. Обновлены OpenAPI/types/CLI/UI; неизвестный cursor не раскрывает чужие записи. Есть detail read конкретного старого operation.

Доказательства: SQL plans и query counts, request tests, UI scenario «старый active / много новых failed или unknown intent».

## Q07 — Интеграции и конкурентные отказы · P1

Расширить доказательства уже существующих idempotency/fencing/unknown механизмов. Определить классификацию: локально отклонённое до отправки; заведомо rejected партнёром; неопределённое после I/O; подтверждённое; требующее operator attention.

Приёмка: remote accepted/response lost; worker killed до/после I/O; lease expired; старый worker завершился после нового; callback раньше response; duplicate и out-of-order callbacks; conflicting sequence; 404 lookup; malformed contract; scanner unavailable; prolonged unknown. Для каждого operation реальные partner logs подтверждают отсутствие второго external effect. Unknown не превращается в success/failure по одному timeout и не скрывается после исчерпания retries; UI/CLI/runbook показывают следующий безопасный шаг.

Использовать управляемые barriers/failpoints и сохранённые seeds для sequence/property checks. Existing happy/negative scenarios сохраняются; не создавать дублирующие tests ради количества.

Доказательства: transition matrix, real HTTP traces без secrets, per-operation partner effect counts, operator diagnostic reports.

## Q08 — Настоящий выпуск, происхождение и совместимость схемы · P1

Выполнить verify → build → scan → GHCR → immutable manifest → deploy → business/file smoke на реальной Linux среде. SBOM/provenance уже включены в build config; дополнить проверяемой политикой происхождения, привязанной к repository/workflow/revision/digest, и отрицательным сценарием подмены.

Проверить expand/contract migration и совместимость предыдущего runtime с новой схемой. Image rollback сохраняет уже применённые миграции, поэтому old API/worker обязан работать с этой схемой и old job payload. Измерить migration lock/duration на выбранном dataset; заранее проверять существующие inconsistent rows перед усилением constraints.

Приёмка: выпуск A успешен; выпуск B успешен; дефектный C отклонён gate/smoke; B восстановлен, данные/очередь/files сохранены. Подмена digest/revision/provenance отвергнута до deploy. Rollback после миграции подтверждён business workflow. Failed-run artifacts сохранены.

Доказательства: настоящие runs, release manifest, verified attestation policy, runtime inventory и rollback reports. [GitHub attestation verification](https://cli.github.com/manual/gh_attestation_verify).

## Q09 — Измеренная производительность и стоимость · P1

Повторить профиль текущей ревизии через реально используемый HTTP/TLS вход. Сохранить старые benchmark results как историческое сравнение. Проверить два профиля: discovery/history reads; mixed commands/uploads/validation/callbacks/queue. Зафиксировать host, dataset, arrival rate/concurrency, warmup, длительность, resources и критерии отказа до acceptance run.

Измерять p50/p95/p99, achieved throughput, ошибки/timeouts, CPU/RSS/allocations/GC, SQL time/materialization/query count, connection pool и lock waits, queue age/drain. Отдельно проверить contention durable metric counter rows и idempotency locks. Показать перегрузку и восстановление, а не только один красивый percentile.

Приёмка: agreed capacity profile соблюдён; no unexpected errors/lost effects; cursor reads bounded; timeouts и degradation предсказуемы; backlog после восстановления убывает. Цифры SLA/RPS не придумывать до определения среды и профиля. Замеры сохраняют raw samples и до/после для каждого заявленного улучшения.

Доказательства: reproducible workload, query plans, profiling report, capacity table и конкретные scaling triggers.

## Q10 — Наблюдаемость пользовательского результата · P1

Сделать durable Prometheus/Alertmanager/receipt storage с ограниченными retention и disk budget. Различать durable business observations и process counters; исключить двойное суммирование общих DB counters при нескольких API replicas. Labels не должны расти по user/operation IDs.

Определить SLIs: успешные пользовательские commands/reads; время до notification effect; validation completion; возраст unknown; queue oldest age. У каждого — denominator, exclusions, окно и источник. Зафиксировать lab SLO и error-budget policy; production target требует реального окна наблюдения.

Приёмка: restart сохраняет нужную историю; normal → failure → delivered firing → recovery → resolved видны; остановка worker отличается от падения HTTP; отсутствие scraper/metrics заметно. Каждому alert соответствует action и runbook. Dashboard позволяет найти одну операцию через correlation ID без secret/PII leakage.

Доказательства: retained timeline, receiver receipts, SLI query tests, restart drill, documented lab observation window. [Google SRE: implementing SLOs](https://sre.google/workbook/implementing-slos/).

## Q11 — Восстановление текущего DB+files+Publishing · P1

Задать RPO/RTO и согласованность backup strategy до упражнения. Включить primary/queue DB, private artifacts, report/history, release state и доступ к recovery keys/config. Восстановить на другой чистой VM при недоступной исходной VM. Partner должен представлять независимую внешнюю систему; companion container на потерянном host не доказывает её доступность.

Приёмка: hashes/private HTTP downloads совпадают; active deployment и validations восстановлены; pending/unknown safely reconciled до разрешения новых external commands; callbacks/replay не создают дублей. Missing/corrupt object обнаруживается и блокирует неправильный publish. Backup encrypted, retention/restore window явно связаны с artifact cleanup; ключи доступны без исходного checkout. Измерены elapsed recovery и допустимая потеря данных; выполнен negative corruption/missing-key probe.

Если выбранное RPO требует online recovery, acceptance включает physical base backup + continuous WAL archive и восстановление на заданную точку времени; pg_dump не используется как WAL base backup. Файлы связываются immutable inventory и сохраняются на всё recovery window. Если принят quiescent snapshot, документировать всех остановленных writers и влияние паузы на SLO.

Доказательства: backup inventory, restore manifest/hash checks, reconciliation trace, RPO/RTO report, runbook. Отдельная VM на том же физическом host доказывает VM failure drill; физическую/offsite disaster tolerance нужно проверять в другом failure domain. [PostgreSQL continuous archiving](https://www.postgresql.org/docs/18/continuous-archiving.html).

## Q12 — Живая инфраструктура текущего runtime · P1

Подготовить чистую Linux VM через текущий Ansible, закрепить версии/config и раздельные migration/runtime роли. Выполнить apply дважды и контролируемый drift/repair. Повторить Helm rollout/rollback и network/worker/DB recovery на актуальных registry digests, с реальной migration ordering. Проверить завершение worker и совместимость leases при rollout.

Приёмка: повторный apply changed=0 кроме заранее объяснённых недекларативных действий; drift обнаруживается/исправляется; positive и negative CNI probes проходят; DB outage снимает readiness, сохраняя корректную liveness; restart/rollout сохраняет private artifacts и queue effects. Limits/requests основаны на измерениях. Registry, DB и PVC architecture documented.

Доказательства: actual Ansible recap, Terraform plan/apply context, Helm history, runtime digests, NetworkPolicy and recovery reports. Current one-node exercise не подтверждает physical HA; topology и failure domain записываются в отчёте.

## Q13 — Читаемость и проверка защит · P1

Сформировать карту доменов и ответственности: transport, authorization, use case, transaction, external adapter, SQL invariant, background recovery. Сохранить idiomatic Rails и короткие проверяемые use cases. Рефакторинг оправдывать конкретным duplicated rule, failure handling или трудностью проверки.

Уточнить типизированные значения на наиболее рискованных границах: money уже имеет Steep scope; partner observations, identifiers и typed errors должны иметь однозначный contract. Не заявлять весь Rails typed, пока проверяется один boundary.

Приёмка: zero new boundary violations; contract tests соответствуют реальным request/response; критические regression tests проваливаются при удалении fingerprint/fencing/HMAC/owner scope/NULL protection. Комментарии объясняют решение/границу, а не пересказывают код. Каждая защищаемая гарантия имеет владельца реализации и один убедительный failure test.

Доказательства: architecture checks, focused mutation/negative-control results, concise ADR с альтернативами и условиями пересмотра.

## Q14 — Честные доказательства и передача проекта · P1

Обновить README/SHOWCASE/execution-status: repo существует, первый remote run красный. Отделить latest accepted revision от historical evidence. Для каждого нового результата указать source revision/snapshot, runtime digests, environment, workload/fault config, tool versions, actual timestamp и raw-report hashes.

Индекс должен проверять schema/context актуального acceptance run, а не только фиксированные 118/13 в прошлых файлах. Хранить компактные sanitized reports/provenance достаточно долго для интервью; текущая Actions retention семь дней требует отдельного durable evidence решения. Ошибочные результаты не переписывать в pass.

Приёмка: другой инженер из clone запускает подготовку, сценарий и диагностику по runbook без личного ignored state. Есть RU technical walkthrough и EN partner incident update. Репетиция на 15 минут завершена; кандидат самостоятельно объясняет invariants, query plan, unknown и rollback после migration. Две реальные коммерческие истории содержат личную роль и измеренный результат; synthetic lab stories обозначены как упражнения.

Доказательства: fresh-clone checklist, reviewer notes, evidence manifest, interview recording/checklist и английский communication sample.

## Порядок исполнения

1. Q01 и первые SQL negative cases Q02: green CI и закрытие конкретных нарушений.
2. Q03, Q06, Q07, Q13: жизненный цикл bytes, bounded APIs, integration crash matrix и понятные Ruby contracts.
3. Q04, Q05, Q08, Q12: безопасный deployment trust, реальная Linux среда, registry chain, schema compatibility и crash recovery.
4. Q09 и Q10: измеренный профиль и наблюдаемость; budgets определяются до финального acceptance run.
5. Q11: recovery новой системы в выбранном failure domain, связанный с retention/cleanup.
6. Q14 и полный acceptance: свежие доказательства и самостоятельный показ.

Каждая реализация — небольшой тематический commit с конкретной причиной, проверкой и outcome. Новые технологии/сервисы добавляются только при доказанной необходимости для одного из критериев и с оценкой эксплуатационной цены.

## Итоговый acceptance record

Для каждого Q01–Q14 записать статус, revision, environment, команду, evidence, результат, предел и unresolved findings. Все P0/P1 приняты; нет необъяснённых critical failures, skipped critical scenarios, lost/private/corrupt artifacts или repeated external effects. Неописанный предел гарантии считается незавершённой работой.

Финальный показ: clone → prepare → business flow → partner bad package → исправление → выпуск → потерянный ответ → диагностика/reconciliation → worker incident/alert → recovery → rejected deployment/rollback → clean restore → explanation of tradeoffs.

Это конечный контракт качества существующего showcase. Multi-region, физическая HA, новое хранилище или дополнительные сервисы требуют отдельного продуктового требования, failure model и бюджета; они не прибавляют оценку автоматически.
