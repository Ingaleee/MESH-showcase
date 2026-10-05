# Проверки рефакторинга backend

8 октября 2026. [Описание дефектов, решений и ограничений](../../backend-hardening.md).

- [Полный RSpec](rspec.json): 90 примеров, без failures и pending.
- [Полный browser E2E](playwright.json): 11 passed, 0 skipped, 0 flaky; сценарии marketplace, предложения, выбор, версии результата и платёжный simulator.
- [Production readiness](production-readiness.json): отдельные API контейнеры с доступной и недоступной PostgreSQL; основной DB service не остановлен.
- [Production runtime](production-runtime.json): image ID, непривилегированный UID и sandbox flags.
- [Brakeman](brakeman.json), [Bundler audit](bundler-audit.json).
- [Manifest исходников и отчётов](verification.json).

RuboCop проверяет все 165 Ruby-файлов, Packwerk — 117; TypeScript, Prettier, 43 OpenAPI operations и module API check прошли. Проверки относятся к локальному стенду. Исторические замеры в общей папке evidence не заявлены повторно выполненными. Удалённый CI и production SLA не подтверждены.
