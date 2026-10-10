# №5 — выбор автора заказчиком

[Живой проект](http://localhost:3100/projects/aed62a01-5ee3-4981-8550-b8f234af31b7). Вход: `client@mesh.local` / `MeshDemo2026!`.

- [Предложения, desktop](owner-desktop.png).
- [Детали рядом со списком](owner-drawer.png).
- [Сравнение](owner-comparison.png).
- [Подтверждение выбора](owner-confirmation.png).
- [Список на телефоне](owner-mobile.png).
- [Мобильная панель](owner-drawer-mobile.png).
- [Production frontend](production-desktop.png).

На демонстрационном проекте подтверждение отменено: он остаётся открытым для просмотра. Примеры во вложениях — изображения MESH, загруженные демо-авторами через обычную файловую модель и проверенные ClamAV. Реальный выбор проверяется на отдельных тестовых проектах.

`browser-check.json` содержит пять ширин без переполнения, результаты Axe для списка и drawer на desktop/mobile и ошибки JavaScript. `production-check.json` проверяет nonce/CSP, приватные изображения, сравнение, избранные, подтверждение и мобильную панель. `playwright-full.json` и `rspec-full.json` сохраняют успешные полные прогоны. `verification.json` связывает отчёты с исходниками и production image.
