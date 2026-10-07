# Реализованная архитектура MESH

Статус: рабочий демонстрационный сценарий. Этот документ описывает код; `architecture-proposal.md` сохраняет более широкий проект решения. Результаты выполнения находятся в `verification.md` и `evidence/`.

## Карта доменов и владение

| Пакет | Данные и ответственность | Разрешённый интерфейс между пакетами |
|---|---|---|
| Identity | Account, пароль, версия сессий | Account: идентификатор и проверка входа |
| Talent | Профиль, навыки, приватные файлы | Directory: поиск и наличие профиля |
| Marketplace | Project, BriefVersion, Proposal, Award | Команды вызываются из composition root |
| Engagements | Соглашение, неизменяемые условия, версии сдачи и принятие | Create, ReadModel.basis |
| Finance | Settlement, PaymentOperation, Ledger, receipts, reconciliation | Команды вызываются из composition root |
| Notifications | Приватная лента уведомлений | Consumer вызывается orchestration job |
| Platform | Idempotency, Outbox, Delivery, Audit, Money, Current | Технические примитивы; бизнес-правила остаются в доменах |

Packwerk проверяет зависимости и циклы. Дополнительная проверка сканирует доступ к константам и строковые ассоциации по `contracts/module-apis.json`. Это не sandbox: динамический Ruby, SQL и reflection остаются предметом review. Controllers, jobs и presenters — composition root и могут соединять пакеты.

## Метод проектирования

Продуктовый сценарий сначала разобран на команды, факты и инварианты: PublishProject → ProjectPublished; SubmitProposal → ProposalSubmitted; AwardProposal → EngagementCreated; SubmitWork → WorkSubmitted; AcceptSubmission → WorkAccepted. Это подготовка к EventStorming с владельцем продукта, а не выдуманная запись реально проведённого воркшопа.

Из DDD применены bounded contexts, общий словарь, агрегатные границы и value object Money. Use cases управляют транзакциями; тонкие controllers отвечают за HTTP и авторизацию. ActiveRecord остаётся persistence model; лишняя абстракция Repository не добавлялась. Provider и scanner находятся за небольшими адаптерами, поэтому отказ внешней системы можно воспроизвести в тесте.

Read models и команды разделены на уровне методов. Это лёгкое CQRS, без отдельного read datastore. События поддерживают эффекты и интеграцию; они не используются для восстановления состояния агрегатов. Event sourcing не реализован.

## Корректность переходов

| Операция | Механизм | Наблюдаемое свойство |
|---|---|---|
| Повтор команды | Actor + operation + key, canonical fingerprint, unique constraint и lock | Сохранённый результат либо конфликт при другом payload |
| Выбор автора | Lock Project, уникальный Award, составной FK Proposal → Project | Один победитель; неверный проект нельзя подставить даже через SQL |
| Изменение брифа | Expected lock_version; новая неизменяемая BriefVersion | Старое предложение не принимается; автор может предложить условия к новой версии |
| Соглашение | Snapshot условий и комиссии; immutable trigger | Изменение исходного брифа не переписывает договорённость |
| Приёмка | Lock Engagement, последняя Submission, составной FK | Принимается конкретная версия своего соглашения |
| Финансовый результат | Lock Settlement → PaymentOperation; operation key | Один журнал на одну операцию; повторное наблюдение безопасно |
| Спор и отправка выплаты | Общий Settlement lock, явная граница dispatching | Hold до dispatch блокирует отправку; после dispatch нужен разбор уже начавшейся операции |

У транзакционных use cases вместе фиксируются состояние, идемпотентный результат, outbox и audit, когда они предусмотрены командой. Ошибка outbox откатывает выбор автора. PostgreSQL работает на Read Committed; критичные строки сериализуются `FOR UPDATE`. Это сознательная стратегия, а не глобальный Serializable без retry policy.

## Деньги и внешняя неопределённость

Money хранит integer minor units, поддерживает RUB/USD/EUR/JPY и запрещает смешивать валюты. HTTP-команды не обрезают дробные числа через `Integer(float)`: вход должен быть integer либо целой десятичной строкой. Use cases дополнительно проверяют Money до записи. Комиссия округляется half-up целочисленно; политика и basis points зафиксированы в соглашении. UI создаёт проекты в RUB; API поддерживает остальные валюты, валюта проекта после создания фиксирована.

PaymentOperation: `requested → dispatching → confirmed / failed / unknown`. Claim имеет lease 30 секунд; сеть вызывается вне транзакции. `unknown` и просроченный `dispatching` сначала проверяются у провайдера. При отсутствии записи допустим повтор только с прежним operation key и в пределах принятого окна 24 часа. За его пределами автоматическая повторная отправка запрещена. Это настройка демонстрационного адаптера; реальный провайдер потребует собственного подтверждённого контракта.

В симуляторе отдельная PostgreSQL DB коммитит результат до искусственной задержки ответа. Таймаут клиента поэтому создаёт настоящее расхождение между локальным состоянием и провайдером. Webhook содержит только подсказку идентификатора; HMAC и timestamp проверяются, receipt сохраняется до обработки, job заново читает доверенный результат у провайдера. Дубликаты receipt подавляются уникальным event ID.

Сверка включает все локальные состояния, в том числе `requested`, восстановленный из старого backup. Поле `reconciled_at` даёт покрытие последовательными ограниченными пачками по 25 операций. Сравниваются ключ, provider ID, тип, валюта, сумма и terminal state. Расхождения сохраняются отдельно; успешная следующая проверка разрешает существующее исключение.

Резервирование: Дт provider_cash / Кт client_funds. Выплата: Дт client_funds на gross / Кт provider_cash на net / Кт platform_revenue на fee. Commit-time constraint проверяет баланс по каждой валюте. Проведённые заголовки и записи нельзя изменить, дополнить или удалить. Роль владельца БД способна менять DDL; поэтому runtime не должен владеть таблицами или иметь TRUNCATE. История защищена в пределах этого trust boundary.

В этой версии одна операция каждого типа на соглашение. Терминальный отказ не превращается автоматически в новый платёжный intent. Refunds, partial payouts, real escrow и chargebacks не реализованы.

## Доставка и отказоустойчивость

Outbox и Delivery находятся в primary DB. Dispatcher фиксирует claim с UUID token и отдельно пишет job в queue DB. Потеря enqueue восстанавливается после lease; потеря ответа от очереди допускает дубликат job. Старая попытка не может сбросить новый claim или увеличить retry count. Consumer создаёт notification и помечает delivery в одной primary-транзакции, unique constraint ограничивает эффект одним уведомлением на пользователя и event.

После пяти durable failures событие переводится в `failed`; backoff хранится в БД. Операторский retry проверяет состояние и записывает audit. Ошибка broadcast не отменяет уже сохранённое уведомление. Action Cable передаёт подсказку, а приватный HTTP endpoint и периодическое обновление остаются источником данных.

Critical payments, events/default и files обрабатываются отдельными процессами worker. Медленный scanner не занимает потоки платежей и уведомлений. Queue DB и gateway DB в демо находятся на одном PostgreSQL сервере, поэтому не доказывается независимость их инфраструктурных отказов. [Дополнительные гарантии и проверка инфраструктуры](backend-hardening.md).

## Безопасность и клиент

Один public origin маршрутизирует Rails и Next.js. Rails использует зашифрованную HttpOnly cookie, SameSite=Lax, CSRF token и origin check. Смена сессии при входе и session_version при выходе предотвращают повторное использование старой сессии; Action Cable connections разрываются. Pundit проверяет участие/владение, операторский доступ назначается отдельно и не приходит из регистрации.

Next.js формирует CSP с отдельным script nonce на запрос. Это требует динамического рендера HTML; immutable JS/CSS остаются кешируемыми. `unsafe-eval` разрешён только dev-сборке; inline styles нужны React style props и анимациям. Политика запрещает frames, plugins и сторонние scripts; см. [официальный подход Next.js](https://nextjs.org/docs/app/guides/content-security-policy).

Файлы проходят MIME sniffing, лимит 10 MB для portfolio/proposal и 20 MB для результата, карантин и проверку upload digest. Скачивание проверяет участие и состояние, отвечает private/no-store и attachment/nosniff. При недоступном ClamAV выдача и приёмка результата с непроверенными файлами блокируются. Scan leases и execution tokens не допускают запись устаревшего ответа. Адаптер проверяет полную NUL-терминированную запись, ограничивает ответ 4096 байт и отправляет бинарные chunks с big-endian длиной по [протоколу ClamD](https://docs.clamav.net/manual/Usage/ClamdProtocol.html). Ответ с обнаруженной сигнатурой `OK` не считается чистым. Антивирусный сервис опционален; тесты с локальным TCP peer и fail-closed не равнозначны проверке реального malware detection.

Frontend использует сгенерированные типы OpenAPI, устойчивый idempotency key до успешного ответа, native dialog, уменьшение анимаций по настройке пользователя, клавиатурный поиск и адаптивные layouts. GSAP отвечает за hero; Motion — за появление карточек. Автоматический axe проверяет конкретные страницы и login dialog; полная доступность всего продукта требует более широкого ручного аудита.

## Наблюдение и границы доказательства

Есть структурированные request logs, correlation ID, Rails/ActiveJob/PG OpenTelemetry instrumentation, сохранение trace context в outbox и отдельный consumer span. Prometheus собирает backlog, возраст события, poison deliveries, unknown payments и reconciliation exceptions. Alert rules подготовлены; реальные инциденты и uptime за длительный период не измерялись.

TLA+ описывает небольшую абстрактную машину выплаты: приёмка, резервирование, hold, dispatch, потеря ответа и повторное наблюдение. TLC проверяет инварианты в её конечном пространстве. Модель не является доказательством всего Ruby-кода, бесконечной живости или поведения реального PSP. RSpec, реальные concurrent connections, browser E2E и restore drill связывают выбранные свойства с реализацией.
