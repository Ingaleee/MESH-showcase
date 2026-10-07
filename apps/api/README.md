# MESH API

Rails 8.1 modular monolith. Подробные инструкции запуска и demo credentials — в [корневом README](../../README.md).

Домены находятся в `packs/`; controllers вызывают use cases, а междоменные обращения проходят через API из `contracts/module-apis.json`. Packwerk проверяет зависимости, дополнительная проверка ограничивает доступ к private constants и associations.

Primary PostgreSQL хранит business state, idempotency, audit, outbox и ledger. Solid Queue использует отдельную логическую DB. Платёжный simulator коммитит внешнее состояние независимо от backend.

Команды внутри API container:

```sh
RAILS_ENV=test bundle exec rspec
bundle exec rubocop
bundle exec packwerk validate
bundle exec packwerk check
bundle exec steep check
bundle exec ruby script/mutation_money.rb
bundle exec brakeman --no-pager
```

RSpec работает только с `mesh_test`; тестовая схема очищается между примерами для настоящих commit-time constraints и concurrent connections. Обычная development DB этим suite не очищается.

Используется SQL structure dump, поскольку Ruby schema не сохраняет deferred triggers. Initializers и новые autoload directories требуют перезапуска API и фоновых процессов.

Production image — `infra/Dockerfile.api`. Обязательны отдельные primary/queue URLs, `SECRET_KEY_BASE`, HTTPS public origin и длинный metrics token. Finance по умолчанию выключен в production. [Runtime SQL role](../../infra/runtime-role.sql) — шаблон для deployment; локальный demo role владеет схемой.

[Реализованные инварианты](../../docs/implementation.md) · [ADR](../../docs/adr.md) · [Runbooks](../../docs/runbooks.md) · [Проверки](../../docs/verification.md)
