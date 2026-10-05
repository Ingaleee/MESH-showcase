# №6 — рабочее пространство автора

[Открыть NORA](http://localhost:3100/workspace?engagement=c3a1bdb8-8264-4164-b1d7-2d06dd70ea2f). Вход: `design@mesh.local` / `MeshDemo2026!`.

- [Текущая версия и история, desktop](workspace-desktop.png).
- [Рабочее пространство на телефоне](workspace-mobile.png).
- [Передача новой версии](new-version-desktop.png).
- [Форма на телефоне](new-version-mobile.png).
- [Зафиксированные условия](frozen-terms.png).

Скриншоты показывают существующее соглашение с двумя сохранёнными версиями и реальным отзывом к первой. Изображения — объявленные демо-материалы MESH; это настоящие приватные вложения, проверенные ClamAV. Новая версия в форме скриншота не отправлена. Browser E2E выполняют запись, замечания и приёмку на собственных проектах.

Проверено 8 октября 2026: **64 RSpec, 11 Playwright**, без failures, skipped и flaky. TypeScript, Prettier, 43 OpenAPI operation IDs, module API check, Packwerk и RuboCop для 23 изменённых Ruby-файлов прошли. Brakeman и Bundler audit не нашли известных проблем в проверенной области.

- [Responsive и Axe](browser-check.json): ширины 320/390/768/1024/1440 px, выбранные состояния без violations и JavaScript errors.
- [Полный RSpec](rspec-full.json) и [полный Playwright](playwright-full.json).
- [Production проверка](production-check.json): matching script nonce, private previews, восстановление черновика, условия и мобильная форма; [desktop](production-desktop.png), [mobile](production-mobile.png).
- [Снимок исходников и SHA-256 материалов](verification.json), [образ](production-image.json), [Brakeman](brakeman.json), [Bundler audit](bundler-audit.json).
- [Повтор обработки события через операторский API](event-recovery.json): доставка обработана, уведомление записано один раз.

Production проверка относится к отдельному standalone frontend с запросами API к существующему локальному Rails; запись и финансовый сценарий проверены отдельно через основной origin. Заражённые файлы и scanner outage воспроизводятся тестами. Это локальные результаты, не удалённая CI attestation или production SLA. [Модель и ограничения](../../workspace-design.md).
