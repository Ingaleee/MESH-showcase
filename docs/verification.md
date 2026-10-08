# Проверенная версия MESH

Дата проверки: 8 октября 2026. Среда: Windows, Docker Desktop с Linux containers, Ruby 3.4.11 / Rails 8.1.4, Next.js 16.4.0 / React 19.3.0, PostgreSQL 18.6. Браузерные проверки выполнялись в headless Microsoft Edge через Playwright 1.63.0.

После [ревизии Ruby backend](backend-hardening.md) добавлены [измерения и восстановление DB/files/queue](architecture-proofs.md), проверены SQL-индексы и deep cursor, реальные очередь/Prometheus и отдельный production API на большой выборке. Повторно выполнены полный RSpec, browser E2E, TypeScript, Prettier, OpenAPI, module API check, Packwerk, RuboCop, Brakeman и Bundler audit. [Текущие отчёты](evidence/architecture-lab/README.md). [Скриншоты и production frontend №6](screenshots/workspace-redesign/README.md), финансовый restore drill, Money/TLC и малый benchmark ниже относятся к предыдущим завершённым прогонам и не объявляются переснятыми.

## Выполненные проверки

| Проверка | Фактический результат | Материал |
|---|---|---|
| RSpec | 94 примера, 0 failures, 0 pending | [JSON](evidence/rspec.json) |
| Browser E2E / accessibility | 11 passed, 0 skipped, 0 flaky | [JSON](evidence/playwright.json) |
| OpenAPI | 43 operation IDs; generated TypeScript совпадает с контрактом | `npm run contract:check` |
| TypeScript | `tsc --noEmit` без ошибок | `npm run typecheck` |
| Ruby style | Все 177 Ruby-файлов API, 0 offenses | [JSON](evidence/architecture-lab/rubocop.json) |
| Frontend style | Все проверяемые файлы соответствуют Prettier | `npm run format:check` |
| Границы | Packwerk validate/check: 126 файлов; module API check прошёл | `package.yml`, `contracts/module-apis.json` |
| Money types | Steep без ошибок в заданном критичном target | `Steepfile`, `sig/money.rbs` |
| Money mutations | Baseline проходит, 3 целевые мутации выявлены | [JSON](evidence/money-mutations.json) |
| Brakeman | 0 security warnings | [JSON](evidence/brakeman.json) |
| Bundler audit | Пустой список известных уязвимостей | [JSON](evidence/bundler-audit.json) |
| npm production audit | 0 известных уязвимостей в проверенных production dependencies | [JSON](evidence/npm-audit.json) |
| TLC | 33 generated / 18 distinct states, нарушений заданных инвариантов нет | [Вывод](evidence/tlc.txt) |
| Production web | Standalone image №6: CSP, nonce, private previews, черновик и UI проверены в браузере | [JSON №6](screenshots/workspace-redesign/production-check.json) |
| Production API | Non-root/read-only/cap-drop image обслуживает публичную ленту; реальный отказ DB даёт ready 503 при live 200 | [HTTP](evidence/backend-hardening/production-readiness.json), [runtime](evidence/backend-hardening/production-runtime.json) |
| Восстановление | Reconciliation восстанавливает `requested → confirmed`; 1 provider POST / 1 journal | [JSON](evidence/restore-drill.json) |
| Живое наблюдение | Prometheus target `up`, Jaeger возвращает недавние spans | [JSON](evidence/observability.json) |
| PowerShell setup | Документированный setup выполнен целиком, exit 0 | [Вывод](evidence/setup.txt) |
| Большие данные | 100 001 проект, 20 000 профилей, 200 001 предложение; before/after SQL, 5 read models, одинаковые ID | [Планы и результаты](evidence/architecture-lab/summary.json) |
| Очередь | Реальный backlog/drain, connection outage, poison budget 5 и firing/resolved alerts | [Материалы](evidence/architecture-lab/README.md) |
| DB + files restore | Counts, SHA-256, missing/corrupt probes, immutable version, private download, fresh queue recovery | [JSON](evidence/architecture-lab/restore-verified.json) |

Сырые отчёты отражают конкретные проверки. `node scripts/check-evidence.mjs` проверяет согласованность их результатов и сохраняет [manifest с SHA-256](evidence/manifest.json) для отчётов и снимка source files. Отсутствие предупреждений сканера не означает отсутствие всех уязвимостей; Steep проверяет Money, а не весь Rails application. Подготовлен `.github/workflows/verify.yml`, но удалённый CI ещё не запускался: репозиторий не опубликован.

## Какие ошибки действительно воспроизведены

RSpec использует настоящую `mesh_test`, отдельные concurrent connections и реальные PostgreSQL commits. Проверяются повтор команды, одновременный выбор двух авторов, rollback при отказе outbox, устаревший бриф и новое предложение к следующей версии, неизменяемые условия/результаты, приёмка чужого результата через SQL, двойное подтверждение платежа, округление комиссии, несбалансированный журнал и изменение проведённой истории.

Проверены гонка hold с dispatch, lost provider response, запрет новой отправки за пределами retry window, сверка старого requested после backup, mismatched provider ID, HMAC/timestamp/deduplication webhook, CSRF, IDOR, приватность предложений, операторский доступ, file quarantine, очередь после lost enqueue, poison delivery, duplicate notification и сбой websocket broadcast. Отдельный тест проверяет продолжение исходного trace через outbox. Structured logs проверены на итоговых 401/404/500 и исключение значений query из JSON log. HTTP-тесты проверяют revision со строковой ISO-датой и отклонение дробных minor units без округления/обрезания; прямой вызов use case тоже не сохраняет ошибочную сумму.

Три scanner tests используют реальный локальный TCP socket: проверяют big-endian framing, передачу 80 000 бинарных байт двумя chunks, clean/infected replies, сигнатуру `OK FOUND`, усечённые и ошибочные ответы. Отдельно демонстрационные вложения и файлы browser E2E проверены настоящим ClamAV daemon; заражённые ответы и outage воспроизводятся контролируемыми тестами, реальный вредоносный файл не использован.

Workspace tests дополнительно проверяют приватность черновиков, SHA-256 реальных байтов, повторное вычисление manifest после чтения JSONB, SQL-защиту истории, cross-engagement foreign keys, гонку приёмки с запросом изменений, потерянный ответ передачи и настоящий ZIP с одинаковыми именами файлов. E2E проходит передачу двух версий, замечание и приёмку последней; черновик восстанавливается после reload. Проверки ширин 320/390/768/1024/1440 px не выявили горизонтального overflow; Axe проверяет выбранные состояния workspace и формы.

Ревизия добавила проверку настоящей restricted runtime role внутри откатываемой транзакции mesh_test, конкурентного общего auth budget, старых outbox claims и lost enqueue response, задержанного scanner clean после нового infected, checksum повреждённых байтов, persistent scanner backoff, запрета приёмки quarantined/rejected файлов и повторного финансового расхождения. Production outage проверяется отдельным контейнером с закрытым DB портом, без остановки общего PostgreSQL.

Browser E2E проходит двумя независимыми сессиями путь публикация → предложение → выбор → передача → приёмка → fund/payout с потерей ответа. Фактические Project/Engagement/Finance/Session ответы сверяются с выбранными OpenAPI schemas; оба журнала сбалансированы. Отдельно проверены фильтры, поиск авторов, отсутствие горизонтального overflow на 390 px, Ctrl+K и native login dialog. Axe проверяет выбранные public pages/dialog по WCAG 2.1 AA; это не полный ручной аудит доступности.

## Большая выборка и восстановление файлов

`pwsh -NoProfile -File scripts/architecture-lab.ps1` воспроизводит отдельный стенд, SQL-планы и 120-second k6. В текущем прогоне 20 req/s, 2 406 HTTP requests / 2 401 iterations, 0 failures / dropped iterations; общий p95 около 81 ms, у самого дорогого маршрута creator search около 94 ms. Проверяются пять маршрутов, включая настоящий подписанный deep cursor за примерно 68 000 open rows. Редкий project search ускорен GIN pg_trgm, deep cursor исправлен с OR на tuple comparison; для выбранных read models SELECT count = 2. [Методика, гарантии и границы](architecture-proofs.md), [summary](evidence/architecture-lab/summary.json).

Restore восстанавливает большую DB и два приватных blob в новые DB/volume, проверяет damage одного байта при прежнем размере, недостающий файл, manifest, SQL immutability, sign-in/CSRF/download и потерю queue DB. Queue восстановлена пустой: старый durable claim повторяется после lease и даёт один notification. Это quiescent local exercise без PITR, object storage или production RTO/RPO. Financial provider reconciliation остаётся отдельным более ранним drill ниже.

## Предыдущий малый benchmark публичного API

Последний воспроизводимый запуск: `powershell -NoProfile -File scripts/benchmark.ps1`.

| Параметр | Значение |
|---|---|
| Runtime | Production image, 1 Puma process, 3 threads, OTEL export выключен |
| Генератор | k6 2.2.0, image закреплён digest |
| Среда | Общий Docker Desktop: 22 vCPU, около 7.47 GiB выделенной RAM |
| Данные | 16 проектов, 6 creator profiles, 8 proposals |
| Запросы | Feed, category filter, creator search; прямой HTTP внутри Docker network |
| Подготовка | Один warmup request на каждый endpoint |
| Нагрузка | 20 iterations/s × 30 секунд; 20 заранее выделенных VUs |
| Результат | 601 iterations, 604 HTTP requests с учётом warmup |
| Ошибки / пропуски | 0 HTTP failures, 0 failed checks, 0 dropped iterations |
| Latency | median 7.44 ms; p95 25.01 ms; max 463.55 ms |

Все четыре thresholds прошли; [метрики](evidence/k6.json), [условия](evidence/benchmark-environment.json), [выполнение runner](evidence/benchmark-script.txt). Здесь не измерены TLS/Caddy/SSR, writes, большой dataset, длительный soak, отказ PostgreSQL или предельная ёмкость системы. По этому результату нельзя утверждать поддержку коммерческой нагрузки или SLA.

Сохранён [первый прогон](evidence/k6-cold.json): при холодных путях и динамическом выделении VUs получены 590 requests и 10 dropped iterations, хотя latency threshold прошёл. Затем warmup стал явной частью runner, а все 20 VUs выделяются заранее. Threshold пропусков сохранён; финальный результат получен без параллельного setup или E2E.

## Восстановление и production runtime

Restore drill создаёт snapshot до внешней операции, затем отдельно коммитит provider state и восстанавливает временную DB. **Сначала reconciliation должен восстановить подтверждение**, затем дублирующее наблюдение проверяет идемпотентность. В последнем прогоне elapsed 5.3 s, provider POST = 1, recovered journal = 1, immutable trigger сохранён, payouts выключены. Это время маленького локального упражнения, а не измеренный production RTO. PITR, object storage, очередь и региональный отказ не проверялись.

Исходная production проверка подтвердила разные script nonce на запрос и Ctrl+K. Проверка №6 повторно проверяет nonce всех script tags, отсутствие `unsafe-eval`, hydration, приватные превью, сохранение черновика и условия; CSP violations и JavaScript errors отсутствуют. Это проверка standalone web с API через локальный development стенд; продуктовый E2E отдельно выполнен через основной Caddy.

При запуске non-root API image была найдена и исправлена ошибка прав `/app/tmp`: source и gems принадлежат root, writable runtime directories — пользователю `mesh`. Реальный HTTP benchmark проверяет больше, чем одно успешное eager loading.

## Границы текущей версии

Finance — независимый simulator без реальных денег. Реальный PSP, refunds, partial payouts, chargebacks и новые intents после terminal failure не реализованы. Один автор на проект и комиссия 10% — демонстрационные продуктовые гипотезы. ClamAV service опционален и включён для текущего стенда; проверены чистые файлы, а обнаружение настоящего вредоносного образца не подтверждено. Публичный доступ к файлам не реализован.

Runtime SQL role проверен отдельным тестом с настоящими правами и подготовлен как template; demo API продолжает работать с development owner. Полный deployment всей системы под runtime role не проверен. Базы primary/queue/gateway логически раздельны на одном PostgreSQL instance. Alert rules подготовлены, но Alertmanager routing, production retention и длительный uptime не измерены. TLA+ относится к небольшой конечной модели и не доказывает весь Ruby code или liveness; full mutation coverage и полный API schema coverage не заявляются.

Следующий коммерческий этап требует утверждённой механики продукта, provider contract, deployment с TLS/secrets/restricted roles, backup policy для DB и файлов, полного security review и нагрузочной проверки на репрезентативных данных. Это отдельные условия готовности к реальному запуску, а не свойства, приписанные текущему стенду.
