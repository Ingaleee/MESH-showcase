# Reliability acceptance: 9 октября 2026

Проверенный release `f15af36d1d5a22b98fac1b466275096a5a0f1355`. Работа выполнена в MESH-showcase; основной MESH не изменён. Это приёмка четырёх конкретных эксплуатационных вопросов и выделенного clean boundary, с заявленными пределами. Она не является независимым аудитом или обещанием универсальной production-готовности.

| Проверка                                               | Выполненный GitHub run                                                           | Доказательство                                                  |
| ------------------------------------------------------ | -------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| Ruby / frontend / security / alerts                    | [CI](https://github.com/Ingaleee/MESH-showcase/actions/runs/37869060208)         | [Manifest](evidence/reliability-oct09/ci/manifest.json)         |
| Signed registry release / exact digest scan            | [Release](https://github.com/Ingaleee/MESH-showcase/actions/runs/37869324980)    | [Manifest](evidence/reliability-oct09/release/manifest.json)    |
| Ubuntu / Ansible / mixed load / interrupted deployment | [Ubuntu](https://github.com/Ingaleee/MESH-showcase/actions/runs/37872648042)     | [Manifest](evidence/reliability-oct09/ubuntu/manifest.json)     |
| Source VM loss / encrypted restore / resumed work      | [Recovery](https://github.com/Ingaleee/MESH-showcase/actions/runs/37871090618)   | [Manifest](evidence/reliability-oct09/recovery/manifest.json)   |
| Terraform / CNI / Helm / worker and DB faults          | [Kubernetes](https://github.com/Ingaleee/MESH-showcase/actions/runs/37870973532) | [Manifest](evidence/reliability-oct09/kubernetes/manifest.json) |

Raw report bytes and their SHA-256 are retained in Git. GitHub artifacts have finite retention; URLs/run metadata do not turn this local catalogue into a signed CI attestation. Deployment additionally checks the actual signed image provenance. `npm run test:reliability:evidence` verifies report hashes, accepted conclusions, release/digest binding and negative-control outcomes.

## Смешанная нагрузка и перегрузка

Ephemeral Ubuntu, production Alpine digests, TLS, ограниченная DB-роль. 10 000 synthetic catalog rows, open arrival schedule, 50% reads / 25% new commands / 25% same-key replays; client limit 40 in flight. Puma 6 threads, admission limit 5 per process. Baseline gate p95 ≤1500 ms was declared before execution.

| Phase                    | Запросов/с | Попыток | HTTP statuses                        | p95 всех ответов, ms | p95 только 200/201, ms | Client drops |
| ------------------------ | ---------- | ------- | ------------------------------------ | -------------------- | ---------------------- | ------------ |
| baseline                 | 5          | 150     | 200: 76, 201: 74                     | 104.3                | 104.3                  | 0            |
| ramp20                   | 20         | 300     | 200: 150, 201: 150                   | 23.3                 | 23.3                   | 0            |
| ramp60                   | 60         | 900     | 200: 444, 201: 446, 429: 10          | 31.0                 | 27.2                   | 0            |
| ramp120                  | 120        | 1800    | 200: 888, 201: 874, 429: 38          | 49.1                 | 49.8                   | 0            |
| controlled_db_contention | 60         | 600     | 200: 128, 201: 125, 429: 344, 503: 3 | 22.0                 | 25.3                   | 0            |

Отказ admission возвращает 429/Retry-After. Последний этап удерживает SQL SHARE lock 6s; это намеренная конкуренция, а не естественная production нагрузка. Быстрые 429 могут улучшить общую percentile: успешная latency показана отдельно. Throughput успешных ответов не равен заданному arrival rate.

Все 937 логических команд доведены до результата, включая повторное принятие ранее отклонённых команд после нагрузки: столько же проектов, событий, processed deliveries и уведомлений; duplicates=0, pending=0. Это не утверждение, что все команды были приняты во время пика. Telemetry: 28 samples, max connections 33/80, max lock waiters 5, API peak observed CPU 75.77%, memory 283.1MiB. API ограничен 1 CPU и 640MiB. Подтверждены насыщение admission и bounded SQL ожидание; временная выборка не измеряет физический потолок всей машины.

Readiness latency 17.3ms измерена после завершения фаз; final backlog verification 2088.3ms — после последовательных recovery/replays. Это не время полного восстановления инцидента. Нет экстраполяции на production, долгого soak, больших ZIP uploads или нескольких API replicas. [Raw workload/resources](evidence/reliability-oct09/ubuntu/mixed-load.json).

## Аварийные переходы deployment

Настоящий SIGKILL в восьми фазах: intent, runtime, migrated, services, smoke, verified, previous, current. Прерывается отдельный старый release, затем восстанавливается текущий подтверждённый baseline f15af36; digests и smoke проверяются, схема не откатывается. Времена упражнения: 9.2s, 9.2s, 19.4s, 51.9s, 52.9s, 52.1s, 53.4s, 52.7s.

Также выполнены SIGKILL самой recovery, недоступность Docker engine при recovery, сохранение current/journal, последующее успешное восстановление и отказ при повреждённом journal. OS flock наследуется дочерней Docker-командой. Повреждённые метаданные требуют расследования по runbook; их автоматическая реконструкция не заявляется. Kernel power loss, все возможные interleavings и HA не проверены. [Raw faults](evidence/reliability-oct09/ubuntu/crash-recovery.json), [runbook](runbooks.md#invalid-journal-and-failed-recovery).

## Потеря исходной VM

Source job завершён до target; UUID виртуальных машин различны. Target не получает source filesystem/volumes. Primary+queue dumps, private-byte inventory и независимо сохранённое состояние партнёра передаются только в AES-256-GCM archives. Ключ доступен target из отдельного secret; второй экземпляр ключа в Windows Credential Manager. После hosted восстановления ciphertext скопирован на Windows и аутентифицирован локально без обращения к GitHub; inventories проверены в памяти, plaintext не сохранён.

Восстановлены 38 primary tables, 15 queue tables и 2 private objects (394 bytes) в минимальном synthetic Publishing fixture; авторизованное скачивание имеет правильный SHA. Отрицательные проверки: wrong key, truncated/tampered archive и missing private object. После сверки pending operation стала confirmed, signed callback replay не дублируется, внешний POST count 2 → 2 → 2 после возобновления workers.

Реальный Puma работает с `mesh_runtime`: /ready, login, private download и anonymous denial; новая команда + same-key replay создали одну запись и одно уведомление. Worker/dispatcher действительно возобновлены. RTO 76.6s ≤ 900s от первого target step, включая checkout/pulls/bootstrap и функциональную проверку; ожидание runner исключено. Этот RTO относится к малому fixture, а не к объёму production data. Runtime HTTP probe использует loopback и production assume_ssl; новый TLS transport test не заявляется, он выполнен отдельно на Ubuntu.

RPO=0 только на quiescent snapshot barrier. Post-snapshot marker намеренно потерян. Цена: запись остановлена, online WAL/PITR отсутствует. Hosted copies хранятся 30 дней; Windows ciphertext/key custody независимы от GitHub, но автоматическая retention и failover при потере GitHub не реализованы. Simulator восстановлен из independently captured state ahead of backup; это не утверждение о непрерывной доступности реального партнёра. [Recovery details](fresh-vm-recovery.md), [raw report](evidence/reliability-oct09/recovery/restored.json), [independent custody](evidence/reliability-oct09/recovery/independent-custody-proof.json).

## Результат пользователя и цели надёжности

Durable mature cohorts учитывают завершённые, failed и unfinished операции: notification 30s, validation 60s, deployment 120s, initial lab objective 99%. Moving 24h gauges не являются counters. Validation rejection — полезный ответ; notification — запись в inbox, не WebSocket receipt. Нет трафика — недостаточно данных.

Настоящая остановка worker: HTTP остаётся доступным, 50 незавершённых уведомлений входят в denominator; alert `ShowcaseUserOutcomeLate` доставлен 2026-10-09T01:33:58.692Z, resolved 2026-10-09T01:34:08.693Z. После recovery 50 once-only effects, replay добавил 0 observations. Late completion не возвращается в good numerator: бюджет показывает пережитую задержку после очистки backlog. Проверены PromQL negative controls, отсутствующий scrape/SLI не трактуется как успех. [SLI definition](user-reliability-objectives.md), [raw drill](evidence/reliability-oct09/ci/worker-incident-summary.json).

Цели — отправная точка lab, а не измеренный 30-day production SLO. Для production нужны требования пользователей и репрезентативное окно.

## Ruby и направление зависимостей

146 RSpec / 0 failures в development и 146 / 0 в native Alpine; 13 browser / 0 skipped/flaky. Rails-free Domain/Application suite и dependency negative control проверяют новую границу; DB/concurrency tests сохраняют гарантии адаптеров.

Строгая Clean Architecture реализована для внешнего publication execution: Domain — правила claim/lease/identity/fencing; Application — workflow и ports; Infrastructure — AR/HTTP/storage adapters; Presentation — API/job/CLI; composition root связывает реализации. Infrastructure зависит от ports Application; Application не импортирует concrete infrastructure. Остальной backend остаётся modular Rails monolith, и не назван целиком framework-independent. [Architecture map](clean-architecture.md).

Kubernetes повторён на этой же source revision/digests: Terraform drift/repair, migration ordering, CNI ingress/egress allow+deny, 50 once-only effects, database ready=503/live=200 без API restart, registry rollout и rejected Helm upgrade/rollback. Ansible второй apply changed=0. Single-node ephemeral K3s не доказывает HA.

## Сохранённые неудачи и границы

[Failed attempts](evidence/reliability-oct09/failed-attempts.json) сохраняют Brakeman dynamic SQL rejection, browser failures при слишком тесном admission, заблокированный release, ошибку init wait, отказ binary extraction с UTF-8, один пропуск TLS client arrival, пропуск случайного secret-scan canary и отказ запуска non-root Puma из-за tmpfs permissions. Canary стал детерминированным; filesystem regression сохраняет отрицательный и положительный контроль. Исправления прошли свежие проверки. TLS read gate сохранён без ослабления: отклонённое измерение имело 299 HTTP 200 и один клиентский пропуск; его точная причина не установлена по end-of-run stats. Final accepted run обязан выполнить исходный профиль без пропусков. Restore и deployment runs остановились до запуска упражнения при GitHub attestation API 503; оба повторены без изменения подписи/gates. Отменённые промежуточные release runs не выдаются за failures приложения или за принятые проверки. Private backup/keys не публикуются.

Четыре выбранных пробела закрыты для этой ревизии и модели стенда. Это не устраняет границы Q01–Q14 автоматически: коммерческие истории/личная репетиция, независимый security review, online migrations/HA/PITR и полная crash matrix требуют отдельного основания. [Quality criteria](quality-bar.md) сохраняют такие границы.
