# Выпуск из неизменяемых образов

Все команды из MESH-showcase. Это отдельное локальное HTTPS окружение, не основной продукт.

```powershell
node scripts/prepare-environment.mjs deployment
docker build -f infra/Dockerfile.api -t mesh-showcase-api:release .
docker build -f infra/Dockerfile.web -t mesh-showcase-web:release .
docker build -f infra/Dockerfile.postgres -t mesh-showcase-postgres:patched .
docker build -f infra/Dockerfile.scanner -t mesh-showcase-scanner:patched .
docker pull caddy:2.11.7-alpine@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f
docker tag caddy:2.11.7-alpine@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f caddy:2.11.7-alpine
node scripts/release.mjs manifest .cache/deployment/release.json mesh-showcase-api:release mesh-showcase-web:release
node scripts/check-images.mjs .cache/deployment/release.json
node scripts/release.mjs deploy .cache/deployment/release.json
node scripts/release.mjs smoke
node scripts/release.mjs rollback
```

Секреты создаются один раз. Повторная генерация не перезаписывает существующий файл и не ротирует пароль сохранённого PostgreSQL автоматически. V2 release manifest фиксирует API/web/PostgreSQL/ClamAV/Caddy через локальные image IDs; опубликованный выпуск использует GHCR digests. Source-tree hash и dirty marker сообщают, если у копии ещё нет commit.

Deployment удерживает lock, запускает миграцию и grants, ждёт health и выполняет TLS smoke с отдельным CA. При отказе нового выпуска возвращает предыдущие образы; миграцию и данные не откатывает. На первом неудачном выпуске предыдущего manifest нет — требуется исправить первичную установку. Empty/rejected manifest не считается успешным выпуском.

Роль runtime не владеет схемой, не создаёт таблицы и не изменяет immutable history. Grants повторяются после миграции. Владелец БД/симулятор остаются privileged локальными компонентами; это не модель эксплуатации настоящего платёжного провайдера.

Остановка без удаления данных:

```powershell
docker compose --env-file .cache/deployment/runtime.env -f infra/deploy/compose.yaml -p mesh-showcase-release down
```

Эта команда сохраняет volumes. Базу и файлы нельзя удалять ради rollback. TLS CA доверен только smoke; host trust store не меняется.

## Security gate и локальная демонстрация

GitHub release проверяет exact application image digests через Trivy до публикации release manifest. V2 включает также PostgreSQL/ClamAV/Caddy. Reports загружаются и при отклонении; successful build/upload ещё не означает одобренный release. [Текущая review](security-review.md) содержит старые findings и новые exact scans: нынешние проверенные digests прошли строгий gate.

Локальные команды deploy выше предназначены для проверки runtime/rollback на loopback. Они не обходят GitHub gate для внешнего выпуска и сами не вызывают scanner. Перед approved release выполните node scripts/check-images.mjs MANIFEST; nonzero запрещает внешнее продвижение.

[Измеренный frontend build cache](build-cache.md): cold/repeat/source/lockfile с проверкой реальных cached steps. Runtime apt layer нужно инвалидировать отдельно для новых security updates.

Полная проверка runtime и негативный exit-42 release drill: node scripts/check-release-runtime.mjs. Команда ограничена mesh-showcase-release, создаёт synthetic business/file records, проверяет SHA inventory и сохраняет отчёт. Миграции/данные не откатываются.
