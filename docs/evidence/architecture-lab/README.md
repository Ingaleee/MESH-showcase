# Проверки надёжности, 8 октября 2026

[Объяснение методики и границ](../../architecture-proofs.md). Воспроизведение: `pwsh -NoProfile -File scripts/architecture-lab.ps1`, затем `node scripts/check-architecture-evidence.mjs`.

- [Summary и SHA-256 отчётов](summary.json), [выборка](dataset.json), [среда](environment.json).
- [SQL before](queries-before.json), [SQL after](queries-after.json), [размеры индексов](indexes.json), [120-second k6](load.json).
- [Backlog](queue-backlog.json), [drain](queue-drained.json), [producer connection outage](queue-outage.json), [poison budget](queue-poison.json).
- Prometheus: [firing backlog](prometheus-backlog.json), [resolved](prometheus-drained.json), [firing poison](prometheus-poison.json), [time series](queue-timeline.json).
- [Backup inventory](backup.json), [restore copy](restore-copy.json), [integrity/auth/download probes](restore-verified.json), [lost queue recovery](restored-queue.json), [local elapsed](recovery-time.json).
- Текущие проверки кода: [RSpec](rspec.json), [Playwright](playwright.json), [RuboCop](rubocop.json), [Brakeman](brakeman.json), [Bundler audit](bundler-audit.json), [сводка](verification.json), [очистка лаборатории](cleanup.json).

Raw backup и fixtures с lab credentials лежат только в игнорируемом `.cache`; публичные отчёты не содержат session/metrics secrets. Snapshot hashes не являются signed CI attestation. Предыдущие финансовые restore, TLC и browser/frontend отчёты находятся выше и имеют собственную дату/область проверки.
