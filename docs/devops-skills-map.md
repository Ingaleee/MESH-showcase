# MESH: как применить предоставленные DevOps-материалы

Дата: 8 октября 2026. Это сопоставление тем курса с проектом и план будущих доказательств. Пользователь сообщил об опыте Docker и Kubernetes; степень самостоятельного выполнения перечисленных лабораторных, Ansible/Terraform и GitLab CI пока не уточнена. Тексты заданий и названия лекций не считаются доказательством завершения работ. Прикладной код, CI и инфраструктура в этой ревизии не изменялись.

Связанный короткий маршрут: [interview-focus.md](interview-focus.md). Расширенные возможности: [interview-roadmap.md](interview-roadmap.md).

**1. Сопоставление без отдельного учебного продукта**

| Предоставленная тема | Навык | Применение к MESH | Проверка результата |
|---|---|---|---|
| VirtualBox, ручная установка Linux | OS, processes, permissions, networks | Разбор устройства и диагностики Linux host | Пройти request path, найти сеть/порт/права по симптомам |
| Vagrant, SSH, app01/db01/web01 | Повторяемый lab, private network, разделение ролей | При необходимости VM lab: edge, приложение, PostgreSQL | Подъём с нуля по инструкции, SSH и доступ DB только из нужной сети |
| MySQL/WordPress/Apache/PHP | App/DB integration и reverse proxy | Существующие Rails/Next.js/PostgreSQL дают тот же инфраструктурный класс задачи | Реальный workflow, database connection, private files и proxy routing |
| Собственный nginx на Alpine | Образ, runtime user, configuration, mounts | Edge exercise или Nginx-вариант для существующего MESH | Config validation, доступность routes, права tmp/log, корректный stop |
| Docker app + DB | Configuration, persistence, readiness | Production Compose profile для текущего приложения | Только edge открыт, данные живут после replacement, health/smoke реальны |
| Multi-stage build | Build/runtime separation, layer cache | Уже существующие API/web Dockerfiles развить измерениями | Изменение source не пересобирает неизменившиеся dependency layers; сравнить build time/size |
| system/build/runtime | Общая build environment и её версия | Раздельные stages или versioned builder image при повторном использовании | Digest builder, reproducible inputs, runtime без build toolchain |
| Compose и несколько репозиториев | Совместимость отдельно выпускаемых компонентов | Независимые API/web image releases; integration manifest с обоими digests | API/web compatibility и согласованный deployment manifest |
| GitLab CI build/push | Runner, rules, variables, registry | Понятия курса переносим в GitHub Actions для двух образов MESH | Реальный pipeline, path-sensitive jobs, commit/digest, registry artifact |
| Общий CI-модуль | Повторное использование и versioning | Один testable build component/template | Два небольших consumers, inputs, фиксированная версия, собственные tests |
| GitLab CI deploy | Provision/upgrade, environments, сериализация | Первичная установка и обновление одного окружения | Cold deploy, repeat deploy, bad release, rollback, smoke |
| Ansible roles/variables/templates | OS/app configuration | Roles для host/runtime/edge/monitoring | Второй converge без неожиданных changes; изменение одного параметра применяет ожидаемый diff |
| Galaxy/Molecule | Dependencies и роль-тестирование | Pinned role dependencies и Molecule scenario для своей роли | Converge → idempotence → verify; реальный сервис и права проверены |
| Secrets в Ansible | Delivery и доступ к конфигурации | Знакомый кандидату механизм encryption/secret delivery | Secrets не попадают в source/logs/diff; rotation и revocation проверены |
| Terraform modules/loops/conditions | Resource provisioning и reusable infrastructure | Один provider, network/VM/storage либо кластер по scope | Plan/apply, no-change plan, controlled drift и recreate; ownership ресурса однозначен |

Ссылка на учебный [react-spring-app](https://gitlab.com/deusops/projects/react-spring-app) при проверке открыла sign-in page; содержимое репозитория не изучено. Сопоставление основано на тексте присланного задания, не на предположениях о его исходном коде.

**2. Предлагаемый технологический маршрут**

Ruby/Next.js source → tests → Docker build → registry → deployment manifest → prepared environment → rollout → business smoke → наблюдение → rollback/recovery.

Пользователь выбрал GitHub как основное место проектов и портфолио. Демонстрационный pipeline развиваем в GitHub Actions; существующий verification YAML остаётся исходной точкой. Build/release/deploy ещё предстоит реализовать и выполнить. GitLab CI из учебных материалов сопоставляем с GitHub reusable workflows, inputs/secrets, path filters и concurrency. Второй deployment pipeline не добавляем.

Границы владения:

- Terraform создаёт выбранные ресурсы и network/storage topology. Provider и место state определяются при выборе среды; cloud billing/resources не создаются в рамках этого планирования.
- Ansible конфигурирует hosts: users, packages, runtime, templates и service configuration. В этом scope он не должен одновременно управлять теми же app Kubernetes resources, которыми управляет Helm/Kustomize.
- Dockerfiles собирают immutable application artifacts; Compose остаётся быстрым локальным способом проверки.
- Helm либо Kustomize описывает application resources Kubernetes. CI запускает один объявленный deployment mechanism.
- Monitoring и recovery проверяют результат выпуска и жизненный цикл данных.

Если GitOps входит в личный опыт и выбран в demo, ownership app deployment переходит выбранному GitOps controller; CI публикует проверяемый artifact/manifest. Смешанный режим прямого apply и reconciler для одних ресурсов требует отдельного решения.

**3. Что усилить в Docker/Compose**

Сейчас Compose предназначен для разработки: repo bind mount, shared gems, Next dev server, локальные debug ports API/gateway. Production API/web Dockerfiles уже используют multi-stage и non-root runtime. Поэтому задача — подготовить отдельную deployment конфигурацию из готовых images и измерить её свойства.

Проверки: один публичный edge; DB/API/worker доступны по объявленным внутренним путям; секреты поступают выбранным способом; постоянные файлы/DB не живут только в ephemeral container layer; read-only root и необходимые writable paths; health/readiness; graceful termination; реальный business smoke. Developer debug ports можно сохранить в dev override.

Есть Caddy edge. Если задача — показать собственный опыт Nginx, можно подготовить его deployment-вариант с проверкой API, Next assets, private downloads и WebSocket. Решение о замене edge не следует автоматически из текста учебной лабораторной.

Важно различать учебные ограничения и production выбор:

- Alpine — вариант базового образа. В MESH сейчас используется Debian slim для Ruby/Node. Выбор сравнивается по native dependencies, build time, runtime compatibility и размеру. В официальных [Node images](https://github.com/nodejs/docker-node/blob/main/README.md) описана особенность Alpine: musl вместо glibc. Малый размер сам по себе не определяет подходящий runtime.
- External dependency/source volume полезен в dev. Для production dependencies и static build artifacts обычно входят в конкретный versioned image; uploads и данные получают отдельное постоянное storage. Mount не должен незаметно менять artifact, прошедший tests.
- Auto migrations для одного local start допустимы как учебный сценарий. При нескольких replicas migration должна иметь одного владельца и контролируемый release step, совместимый с old/new API/workers.
- Логическое разделение system/build/runtime можно показать stages одного Dockerfile. Несколько отдельных builder images оправданы reuse/ownership, а не названием лабораторной.

[Docker multi-stage builds](https://docs.docker.com/build/building/multi-stage/) и [cache invalidation](https://docs.docker.com/build/cache/invalidation/) задают механизмы. Доказательства для MESH: cold/warm build, изменение только source, изменение lockfile, итоговый размер/runtime contents и тот же image digest в smoke/deployment.

**4. Что усилить в GitHub Actions**

Минимальный будущий pipeline:

1. Lint/types/OpenAPI/architecture и Ruby/DB invariants.
2. API/web build с явными dependencies, BuildKit cache и versioned inputs.
3. Push образов; сохранить API/web digests и commit в release manifest.
4. Environment deployment с migration и проверкой rollout.
5. Реальный smoke; bad release exercise и rollback по manifest.

Path filters и зависимости jobs должны учитывать shared contract, lockfiles, scripts и Dockerfiles. Пропуск jobs и Docker layer cache — разные уровни оптимизации. Cache miss должен давать корректную сборку; cache не является доверенным release evidence.

Общий build шаг оформляем как [GitHub reusable workflow](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows) с workflow_call, inputs, явными secrets, outputs digest и consumer checks. Для одного окружения deployment сериализуем через concurrency; stale runs и отмена во время migration требуют отдельной проверки. Hosted runners используются для PR checks, отдельный repository-scoped runner — для доверенного deployment в локальную VM/Kubernetes. Публичные fork PR не запускаются на runner с deployment доступами.

Runner scope, credentials, registry retention и permissions описываются как часть design. Не считать rootless app container достаточной защитой runner с широким Docker/host доступом. Не запускать privileged/untrusted workloads на основном host только ради демонстрации.

Готово, когда проходят первое развёртывание, повтор, upgrade и rollback, а кандидат может объяснить любую переменную, пропущенный/запущенный job и способ восстановления.

**5. Что показать по Ansible и Terraform**

Для Ansible достаточно небольшой рабочей роли с variables/templates/handlers, контролируемым secret delivery и реальной проверкой сервиса. Второй запуск и targeted configuration change дают больше материала, чем перечень Galaxy roles. [Molecule workflow](https://docs.ansible.com/projects/molecule/workflow/) поддерживает converge/idempotence/verify, которые надо наполнить полезными assertions.

Для Terraform достаточно понятного module interface и одного выбранного provider. Обязательные темы разговора: state, locking при поддержке backend, version pinning, secrets, dependency graph, lifecycle, drift и последствия destroy/recreate. [State locking](https://developer.hashicorp.com/terraform/language/state/locking) зависит от backend. `sensitive` redacts вывод, но не гарантирует отсутствие значения в state; [документация по sensitive data](https://developer.hashicorp.com/terraform/language/manage-sensitive-data) разделяет эти свойства.

Terraform provision и Ansible configuration могут быть одним последовательным exercise. Vagrant lab остаётся альтернативой для VM networking/SSH; оба окружения не обязаны быть полными production deployments до собеседования.

**6. Как измеряется уровень кандидата**

После базового happy path добавляем один отказ и одну операционную задачу: bad image, wrong proxy route, недоступная DB, worker kill, failed migration, secret rotation или restore. Объясняем симптомы, root cause, границу ответственности, безопасное действие и проверку. Неизвестные причины называются гипотезами до подтверждения.

Матрица личного опыта имеет поля: технология; коммерческая/учебная задача; самостоятельная ответственность; результат; доступное доказательство; MESH demo; статус. Пока самостоятельное выполнение не подтверждено, предоставленные лабораторные имеют статус «материал предоставлен», а не «выполнено» или «коммерческий опыт».

Ближайшая подготовка: подтвердить статус работ → выбрать один pipeline/окружение → использовать MESH вместо отдельного WordPress/Spring продукта → сделать reproducible deploy → показать один законченный rollback/incident. Параллельно сохраняем сильный Ruby: database invariants, bounded queries и объяснимые failure semantics.
