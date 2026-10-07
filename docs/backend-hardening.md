# Ревизия Ruby backend и инфраструктуры

8 октября 2026. Ревизия охватывает бизнес-команды, сохранение истории, финансовую сверку, файлы, фоновые доставки, авторизацию и локальные deployment настройки. Зафиксированы конкретные дефекты и проверяемые ограничения; «идеальность» всей системы не заявляется.

## Исправленные проблемы

| До изменения | Реализованное поведение | Проверка |
|---|---|---|
| Лимит входа зависел от памяти одного API процесса | Общий PostgreSQL budget для входа и регистрации: 15 попыток за 3 минуты с первого запроса. Блокировка строки сериализует обращения; отказ содержит Retry-After. В БД хранится HMAC идентификатора с секретом приложения | Конкурентные соединения, истечение окна, очистка cache без обхода лимита, request tests |
| Старый enqueue мог вернуть новую доставку в pending | Каждая outbox попытка получает UUID claim_token. Job и обработчик ошибки меняют только свою попытку; дубликат не увеличивает failure_count. Сохранённые backoff и poison budget соблюдаются | Lost enqueue response с новым claim, stale job, false enqueue, повтор poison job |
| Дубли scanner jobs могли перезаписать состояние файла | Общая база PrivateFileScanJob для трёх видов файлов. Queue claim при начале работы меняется на execution token; результат записывается условно по токену и quarantined. Сетевой вызов выполняется без DB lock | Настоящие параллельные соединения и управляемый задержанный scanner; поздний clean не заменяет новый rejected |
| Retry сканера зависел от Active Job и updated_at | Lease, число попыток и следующий retry сохраняются в primary DB. Dispatcher восстанавливает потерянный enqueue и смерть worker после 60 секунд. Outage оставляет карантин; backoff растёт до 300 секунд | Потерянный enqueue, сохранённый backoff, восстановление scanner |
| Scanner проверял полученные байты без сверки с исходной загрузкой | Active Storage open проверяет checksum; SHA-256 дополнительно сверяется с сохранённым upload digest. Неожиданный ответ scanner не считается clean | Изменённые байты, некорректные ответы ClamD и удалённый draft |
| Заказчик мог принять версию с непроверенными файлами | Приёмка блокирует строки вложений и требует available для всех. Отказ откатывает idempotency command и состояние; прежний ключ можно повторить после clean | Quarantined/rejected не создают Acceptance; после scan прежний ключ проходит |
| Устранённое финансовое расхождение скрывало повторную проблему | Сверка повторно открывает существующий incident; конкурентные наблюдения не создают дубль | Mismatch → clean → mismatch и конкурентное создание incident |
| Загрузка portfolio могла оставить запись без прикреплённого файла | Metadata и attachment записываются в общей транзакции. SHA вычисляется при загрузке; Windows filenames нормализуются; скачивание private/no-store | Отказ attach откатывает metadata; digest и приватные download headers |

В SubmitWork длинные проверки и запись manifest разложены на читаемые выражения без изменения intent fingerprint или истории. Транзакционная граница команды сохранена.

## Инфраструктура

`/up` проверяет жизнь процесса. `/ready` отдельно проверяет primary DB через SELECT 1 с локальным statement_timeout 1 секунду; настройка откатывается вместе с транзакцией. При недоступной БД возвращается 503 без внутренних деталей. Queue и scanner не входят в readiness API: их сбой не закрывает чтение брифов и сохранение команд в primary outbox. Они требуют собственных метрик.

API healthcheck обращается к `/ready`; Caddy ждёт healthy API. Connection pool имеет checkout_timeout 2 секунды, libpq connect_timeout 3 секунды. Это пределы отдельных ожиданий, а не гарантия общего deadline любого HTTP запроса.

Solid Queue имеет отдельные процессы для critical payments, events/default и files. Scanner с одним thread не занимает поток уведомлений; graceful stop worker получает 35 секунд. На текущем Docker стенде эти процессы разделяют хост и PostgreSQL instance.

Production boot требует корректный HTTPS origin и разные секреты достаточной длины для cookies, metrics, gateway и webhook. Известные demo values запрещены. Требование длины не доказывает случайность — deployment обязан генерировать секреты и безопасно доставлять их.

`infra/runtime-role.sql` параметризован для имени БД, runtime role и migration owner. Он не применяется к development автоматически. RSpec применяет настоящий шаблон внутри откатываемой транзакции в mesh_test и выполняет SQL под созданной ролью: рабочая запись разрешена, DDL/TRUNCATE/отключение trigger и изменения immutable history запрещены. PostgreSQL owner остаётся отдельной границей доверия.

`scripts/check-api-runtime.ps1` запускает два временных production API: непривилегированный пользователь, read-only root, cap-drop ALL, no-new-privileges и ограниченные tmpfs. Второй контейнер подключается к закрытому PostgreSQL порту. Это проверяет реальный отказ соединения без остановки общей БД. После проверки удаляются только созданные контейнеры. Для загрузок в реальном deployment нужен отдельный writable storage volume или object storage.

Prometheus отделяет активный outbox backlog от parked failed deliveries. Добавлены количество quarantined files, возраст старейшего и число scan errors, а также alert на задержку проверки. CI теперь включает настоящий scanner и ждёт его готовности перед E2E. Удалённый GitHub CI пока не выполнялся.

## Проверка и выпуск

Миграция `20261008040000` добавочная. На локальном стенде перед её выполнением остановлены dispatcher/worker; затем применена схема, обновлён код и перезапущены процессы. Существующие версии и бизнес-история не переписаны. Для rolling deployment сначала обновить схему и consumers, затем dispatcher: прежний job class не принимает второй аргумент claim token. Старые queued jobs без token совместимы с новым reader; актуальный dispatcher восстановит lease.

Команды воспроизведения:

```powershell
docker compose exec -T -e RAILS_ENV=test api bundle exec rspec
docker compose exec -T api bundle exec rubocop
docker compose exec -T api bundle exec packwerk validate
docker compose exec -T api bundle exec packwerk check
npm run contract:check
npm run typecheck
npm run format:check
npm run test:architecture
npm run test:e2e
docker build -f infra/Dockerfile.api -t mesh-api:hardening-verification .
powershell -NoProfile -File scripts/check-api-runtime.ps1
```

[Отчёты и снимок исходников](evidence/backend-hardening/README.md). Предыдущие load benchmark, TLC, money mutations и restore drill остаются историческими проверками и при этом рефакторинге повторно не выполнялись.

## Следующие ограничения

Rate limiter использует primary DB и HMAC со стабильным secret_key_base. Смена секрета сбрасывает идентификаторы budgets; массовая распределённая атака требует отдельного решения на edge. Старые buckets чистятся ограниченными пачками после суток; запросы к ним не продлевают окно отказа.

Scan leases допускают повтор сетевой проверки после зависания. Они ограничивают запись устаревшего результата и не обещают ровно один внешний вызов. Outage не переводится автоматически в rejected: файл остаётся quarantined, retry продолжается с ограниченной частотой, оператор ориентируется на метрики. Гарантии доставки также ограничены атомарным primary effect и дедупликацией, а не отсутствием дублирующих jobs.

Полная проверка backup DB вместе с файлами, PITR, S3 retention, запуск всей системы под ограниченной runtime role, реальные PSP, длительная нагрузка и внешний security review ещё необходимы для коммерческого deployment. Новые локальные проверки не подменяют эти требования.
