# Измеренный BuildKit cache — frontend runtime

8 октября 2026, один локальный прогон четырёх случаев в отдельной временной копии build context. Исходники приложения не изменялись. [Summary](evidence/build-cache/summary.json) и raw progress logs сохраняют реальные ответы BuildKit.

| Изменение | Время | npm ci cached | Next build cached | Runtime apt cached |
|---|---:|---|---|---|
| Cold instructions: --no-cache, base уже скачан | 84,203 s | Нет | Нет | Нет |
| Тот же context | 3,945 s | Да | Да | Да |
| Comment в page.tsx | 53,868 s | Да | Нет | Да |
| Metadata field в package-lock.json | 83,756 s | Нет | Нет | Да |

Изменение lockfile проверяет инвалидирование слоя, не переход на новые версии зависимостей. Source comment проверяет COPY boundary. Runtime apt updates находятся отдельно от application build; повторная сборка использует этот кэш. Чтобы получить новые security packages при неизменном Dockerfile/base, нужно явно инвалидировать runtime apt stage — автоматического ежедневного обновления нет.

Это не четыре статистических выборки, не network cold start, не размер transfer в registry и не измерение API image. Времена зависят от занятого shared host. Образ около 138,7 MB по docker inspect Size; compressed GHCR layers отдельно не измерены.

```powershell
node scripts/measure-build-cache.mjs
```

Скрипт копирует только publishable build inputs в .cache/build-cache, собирает собственные tagged images, проверяет expected cache boundaries и сохраняет logs. Временный context удаляется только после проверки абсолютного пути внутри выделенной директории. Собственные tagged images остаются для разбора; глобальный docker prune не выполняется.
