# Выполненная architecture lab в MESH-showcase

8 октября 2026, изолированные logical DB/files и guarded cleanup; Docker/PostgreSQL host общий. Все 19 raw artifacts проверяются scripts/check-architecture-evidence.mjs; SHA-256 в summary обнаруживает изменение bytes, не заменяет подписанную attestation.

[Summary](summary.json): 100001 projects, 20000 profiles, 200001 proposals; HTTP p95 79,0887 ms при 20 iterations/s × 120 s; 2406 requests; 0 failures/drops. DB + files + verification + claim recovery: 65,021 s локально.

| Область | Отчёт |
|---|---|
| Данные и среда | [dataset](dataset.json), [environment](environment.json) |
| SQL/EXPLAIN до и после | [before](queries-before.json), [after](queries-after.json), [indexes](indexes.json) |
| Нагрузка / route thresholds | [k6](load.json) |
| Queue backlog и drain | [backlog](queue-backlog.json), [drain](queue-drained.json), [timeline](queue-timeline.json) |
| Реальная недоступность соединения producer | [outage](queue-outage.json) |
| Poison budget | [poison](queue-poison.json) |
| Prometheus evaluation | [backlog](prometheus-backlog.json), [drain](prometheus-drained.json), [poison](prometheus-poison.json) |
| Backup / restore | [backup](backup.json), [copy](restore-copy.json), [verification](restore-verified.json) |
| Потерянный queue claim | [recovery](restored-queue.json), [elapsed](recovery-time.json) |

Объяснение измерений, отрицательных результатов и цены гарантий: [architecture-proofs](../../architecture-proofs.md). Поиск категории не ускорился в этом прогоне (median 6,827 → 8,365 ms); таблица сохраняет результат. Поиск автора остаётся примерно прежним (71,725 → 69,620 ms).

Первый запуск outage fixture не прошёл: живой dispatcher мог успеть обработать intent до проверки failed producer. Отчёт попытки сохранён в [lab-attempt-1](../showcase-final/lab-attempt-1.json). В exercise producer фазе normal lab dispatcher теперь остановлен; после фиксации pending snapshot возвращается и проверяется обычное recovery. Успешный summary относится к новому полному прогону, а не к исправлению старого JSON.
