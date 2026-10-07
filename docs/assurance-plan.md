# MESH — план доказательства архитектурных свойств

Дата: 7 октября 2026 года. Статус: **план проверок; частично выполнен**.

Связанный документ: [architecture-proposal.md](architecture-proposal.md).

План включает выполненные и будущие проверки. Фактические результаты, среда и ограничения перечислены в [verification.md](verification.md). Наличие сценария в этой матрице не означает, что он уже проверен; production guarantees не заявляются.

**1. Матрица риска и проверки**

| Риск | Инвариант | Сценарий | Ожидаемое наблюдение |
|---|---|---|---|
| Два выбранных автора | I1, H1 | Два DB connections выбирают разные Proposal одного Project | Один Award, второй получает conflict |
| Два Engagement | I2 | Два разных HTTP key для одного Award | Один Engagement благодаря business constraint |
| Устаревшее предложение | I3 | Brief изменён между просмотром и выбором | Требуется явное подтверждение новых условий |
| Подмена принятой работы | I5 | Submission изменена после Acceptance | Acceptance продолжает ссылаться на исходную версию |
| Чужие объекты | I6 | Второй actor читает/меняет чужой объект через каждый endpoint | Доступ отклонён; ответы не раскрывают приватные поля |
| Чужие файлы | I6 | Actor использует чужой blob identifier | Attach/download запрещён |
| Утрата прав | I6 | Membership отозвана до replay или исполнения | Следует документированной политике, старый cookie не даёт привилегию |
| Потерянный HTTP response | I7 | Commit завершён, connection закрыта до ответа, клиент повторяет | Один эффект, корректный replay |
| Повтор key с новым body | I7 | Одна key, разная нормализованная команда | Conflict, второй эффект отсутствует |
| Очередь недоступна | I12 | Queue DB недоступна после business commit | Outbox сохраняется; после восстановления эффект доставляется |
| Worker умер после локального эффекта | I8 | Kill после commit consumer до ack | Повтор не создаёт второй эффект |
| Lease истекла | I8 | Два worker одновременно обрабатывают одну delivery | Unique receipt/effect защищают итог |
| Сбой provider после принятия | I10 | Provider принял intent, response потерян | unknown, проверка результата, один финансовый intent |
| Истёк provider idempotency window | I10 | Повтор неизвестной операции после contract TTL | Сверка/разбор вместо слепого нового запроса |
| Разные webhook для одного эффекта | I10 | Два event_id сообщают один payment transition | Один подтверждённый локальный эффект |
| Webhook не по порядку | I10 | Старое наблюдение приходит после confirmed state | Допустимый переход/сверка, статус не откатывается произвольно |
| Dispute против payout | I11 | Параллельные PlaceHold и BeginDispatch | Один установленный порядок; соблюдён cut-off |
| Несбалансированная проводка | I9 | Неравные entries либо прямой SQL обход | Posting отклоняется выбранным DB/application механизмом |
| Повтор ledger transaction | I9, I10 | Дважды применён один source operation | Одна posted transaction |
| Старая queue payload | Совместимость | Old-version job исполняется new-version worker | Совместимая обработка либо контролируемый migration path |
| Потеря websocket | Доступность UI | Disconnect, изменение состояния, reconnect | HTTP восстанавливает актуальное состояние |
| Потеря backup window | Recovery | Restore до уже выполненной provider операции | Payout paused; reconciliation обнаруживает внешний эффект |

Для каждой строки нужны отдельный test/report identifier, commit SHA, конфигурация и ограничения проверки.

**2. Уровни проверок**

Domain tests проверяют вычисления, локальные правила и результат перехода. Clock и внешние effects детерминированы.

Request tests проверяют HTTP-контракт, входные данные, actor, policy scope, version conflict и error shape.

DB integration tests используют PostgreSQL: настоящие constraints, rollback, commit и разные connections.

Concurrency tests управляют интерливингом через barrier. Случайные sleeps не являются способом воспроизведения гонки.

Consumer tests повторяют и переставляют events, прекращают обработку в выбранной failpoint и проверяют конечное состояние.

Adapter contract tests имеют общий набор assertions для simulator и реального sandbox. Неподдерживаемые возможности gateway не скрываются универсальным интерфейсом.

Playwright проверяет один полный journey через настоящий Rails backend и PostgreSQL. Внешний provider может быть simulator; UI и внутренние команды не подменяются фиктивным успехом.

Mutation tests ограничены денежной арифметикой, eligibility и важными transitions. Выживший mutant разбирается, а метрика не считается доказательством всей системы.

Security tests перечисляют субъект, действие, ресурс и состояние. Покрываются списки, экспорт, signed links, jobs, Cable и административные операции.

**3. Properties и генерация последовательностей**

- Для Money несовместимые валюты не складываются.
- Комиссия следует явно выбранным правилам округления и ограничениям.
- Каждая posted transaction сбалансирована отдельно по валюте.
- Reversal корректирует исходную transaction без переписывания её entries.
- Повтор intent не увеличивает количество финансовых effects.
- Запрещённый transition не меняет агрегат и не оставляет outbox event.
- Accepted SubmissionVersion сохраняет идентичность после последующих изменений.
- Любой валидный порядок retry/restart сохраняет safety constraints.
- Локальный business failure не оставляет частичный Award/Engagement.

Генератор создаёт последовательности команд и отказов. Seed сохраняется для воспроизведения. Reference model намеренно проще implementation и проверяет бизнес-результат.

**4. Fault injection в локальном/staging стенде**

Контролируемые failpoints:

1. Перед business commit.
2. После business commit, до HTTP response.
3. После записи outbox, до enqueue.
4. После enqueue, до dispatcher progress update.
5. После local consumer commit, до acknowledgement.
6. После принятия provider request, до сохранения результата.
7. После durable webhook receipt, до обработки.
8. Во время lease expiry и повторного claim.
9. После snapshot projection, до catch-up.
10. В момент остановки old worker при rollout.

Failpoint включается только в тестовой конфигурации и не доступна публичному actor.

Для каждого случая проверяем business tables, operation state, outbox/deliveries, provider simulator history, audit и observable alert. Отсутствие exception в тесте недостаточно.

**5. Предлагаемый TLA+/PlusCal пилот**

Начать с Award: два actor, два Proposal, одна Project, retry, потеря response. Safety: количество Award ≤ 1; Engagement соответствует выбранному Award.

Для Finance добавить отдельную небольшую модель Settlement: hold, dispatching, external_success, unknown, retry и confirmation.

Safety: hold-before-dispatch запрещает начало dispatch; один operation не создаёт повторный effect в рамках явно заданного provider contract.

Liveness задаётся условно: при восстановлении worker/provider, fairness и успешной обработке процесс достигает terminal state либо operator attention. Постоянно недоступный провайдер не позволяет обещать completion.

В модель отдельно вводится expiry provider key, чтобы показать, где безопасный retry перестаёт следовать из прежних предпосылок.

TLC results фиксируют bounds, assumptions и число проверенных состояний. Прохождение модели не доказывает соответствие Ruby implementation; соответствие проверяется отдельно.

**6. Воспроизводимый benchmark**

Первый лабораторный workload — предложение, подлежащее калибровке:

- Dataset: 100 000 Projects, 500 000 Proposals, 10 000 Engagements.
- Распределение: обычные и популярные категории, крупные заказчики, skew по участникам.
- Нагрузка: 80% чтений, 20% команд; стартовая контрольная точка 100 requests/s.
- Warm-up, steady state, burst, queue backlog и provider slowdown отдельными фазами.
- Зафиксированные hardware, Postgres/Ruby/Rails версии, dataset seed и network topology.
- Отдельно измеряем command latency, read latency, lock wait, DB pool, queue/outbox age и resource cost.

Числа описывают стенд и цель эксперимента. Они не являются обещанием достижимой пропускной способности.

Success criteria выводятся из SLO proposal после baseline. Failed requests, dropped load и business conflicts видны в отчёте.

Профилирование определяет причину: SQL, serialization, Ruby CPU, allocations, locks, connections или внешний provider. После оптимизации повторяем тот же сценарий.

**7. Disaster recovery drill**

1. Создать данные, файлы, pending events и PaymentOperation с external success.
2. Сохранить согласованный backup snapshot и отдельно известное состояние provider simulator.
3. Выполнить изменения после snapshot.
4. Восстановить новый изолированный стенд.
5. Запустить application в режиме запрета новых financial dispatch.
6. Проверить доступ и соответствие ссылок на объекты.
7. Запустить reconciliation и восстановление pending processes.
8. Проверить отсутствие повторного внешнего эффекта.
9. Измерить RPO/RTO и перечислить потерянные либо восстановленные классы данных.
10. Сохранить report и обновить runbook.

Recovery считается подтверждённым после восстановления и проверок, а не после успешного создания backup.

**8. Architecture fitness и release gates**

| Gate | Что блокирует |
|---|---|
| Dependency/public boundary checks | Новая запрещённая зависимость |
| Contract schema and response validation | Реализация расходится с описанием API |
| Backward compatibility checks | Несогласованное ломающее изменение |
| Domain/DB invariants suite | Нарушение критического правила |
| Critical concurrency/failure suite | Повтор/гонка приводит к некорректному эффекту |
| Security checks | Обнаруженный необработанный риск в выбранном scope |
| Migration compatibility | Old/new приложение не может пройти rollout |
| Reproducible build and dependency inventory | Невоспроизводимый/неидентифицируемый artifact |

Benchmark и restore drill запускаются на соответствующих этапах и после значимых изменений риска; их не повторяют без причины на каждом простом изменении UI.

**9. Evidence package для ревью**

Для каждого сильного свойства храним: проблему, принятое решение, alternatives, test/report, trace/dashboard, ограничения и пример восстановления.

Формат incident note: пользовательский эффект, timeline, причины, сработавшие защиты, недостающие защиты, исправление и способ проверить его.

Формат demo:

1. Показать пользовательский journey.
2. Объяснить один критический инвариант.
3. Воспроизвести гонку или controlled failure.
4. Найти операцию через correlation/operation ID.
5. Восстановить её штатным способом.
6. Показать ADR и фактический test report.

Текущий статус всех evidence: planned. При реализации статус меняется на verified только по реально полученному результату.
