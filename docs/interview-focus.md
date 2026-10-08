# Маршрут подготовки к BGaming

Главный материал — Ruby инженерный цикл: принять пакет партнёра, проверить, выпустить, увидеть сбой, собрать диагностику и безопасно восстановить состояние. Frontend делает сценарий видимым; Docker/Kubernetes/Terraform показывают инфраструктурную часть через реальные упражнения.

| Требование присланной вакансии | Что можно показать сейчас                                                                                      |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| Ruby / сложные задачи          | 131 current hosted RSpec examples, transactions/constraints, bounded reads, fenced claims, uncertain outcomes  |
| Автоматизация выпуска          | ZIP/manifest validation, exact digest/policy, operator API и Ruby CLI, immutable runtime inventory             |
| Поддержка внешних студий       | Stable error codes + fix, independent simulator, diagnostic report и EN partner update                         |
| Production investigation       | HTTP vs worker health, real delivered alerts, replay-safe recovery, clean DB+files restore                     |
| Docker / Kubernetes            | Native production parity, strict image scan, live Helm rollback, real NetworkPolicy denies, readiness/liveness |
| IaC                            | Actual Terraform apply/drift/repair; Ubuntu Ansible second apply changed=0; signed rollout/rollback                   |
| Frontend / разные языки        | TypeScript Next.js UI, отдельный Node partner, 13 full browser scenarios                                       |
| AI tools / коммуникация        | Проверяемые гипотезы, сохранённые failures, postmortem; кандидат объясняет свои решения сам                    |

[Фактический статус](execution-status.md), [демо на 15 минут](interview-demo.md), [Publishing architecture](publishing-lab.md), [Kubernetes evidence](kubernetes-live-lab.md) определяют уже подтверждённые утверждения.

## Следующие внешние шаги

GitHub repository опубликован; verify/build/scan/GHCR имеют реальные successful runs. Для Ubuntu convergence/deploy/rollback и registry Kubernetes выбран временный hosted stand, который не требует покупки VPS или настройки SSH пользователем. Выполненные outcomes публикуются в execution-status.md; конфигурация не считается acceptance result.

Production SLO/HA/PITR/offsite требуют подходящей среды и данных, а не добавления ещё одного YAML. Local one-node cluster — реальный rollout/network-policy lab, с явно указанными ограничениями.

## Подготовка кандидата

Самостоятельно пройти сценарий, открыть transaction/SQL, объяснить каждую гарантию и её границу. Написать две личные коммерческие истории: deployment/infra и investigation/incident, с собственной ролью, данными и измеренным результатом. Этот проект не создаёт задним числом пять лет коммерческого опыта.

Modular monolith помогает согласованности; durable polling имеет цену; Active Storage + SQL upload не атомарны: durable upload intent, fencing и tombstoned cleanup закрывают конкретный lifecycle; unknown честнее blind retry; rollback images не откатывает миграции; private PVC и two replicas не создают HA. Это темы для сильного инженерного разговора.
