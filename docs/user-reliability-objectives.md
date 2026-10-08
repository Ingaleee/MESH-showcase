# User outcome SLIs and lab reliability objectives

HTTP success does not imply a completed notification, validation or release. Histograms of completed work omit abandoned operations. The durable cohorts in UserOutcomeMetrics include them.

Each scrape evaluates records accepted in the preceding 24h, excluding only the newest deadline interval while those operations are immature. Numerator: terminal completion within the deadline from created_at. Denominator: every accepted mature record, including failed and still unfinished work. A validation rejection is a valid completed answer; an infrastructure failure is not. Notification means an effect committed to the inbox, not guaranteed WebSocket delivery. Deployment means verified partner confirmation persisted locally. Retry and callback duplicates reuse the same record and do not inflate the denominator.

| Operation | Deadline | Initial lab objective | User impact |
| --- | --- | --- | --- |
| notification | 30s | 99% | Inbox event has not arrived |
| validation | 60s | 99% | Partner cannot obtain a validation decision |
| deployment | 120s | 99% | Operator cannot know which version is active |

The 24h cohort is a moving gauge, not a monotone counter: do not apply rate() to it. Export from one authoritative API per logical database; do not sum the same rows across API replicas. Pending/failed ages cover all retained unfinished records even outside the SLI cohort. No traffic means insufficient evidence, not 100% success.

For HTTP, use route/method bounded labels; 5xx availability and latency counters reset with the Puma process. Keep 429 admission signals separate. Metrics endpoint errors and absent scraping are failures of observation and must alert. The /ready probe includes primary/queue connectivity.

Objectives are engineering starting points for this demo, chosen above normal local operation and below the interval a human operator would tolerate. They are not measured production commitments. Production targets need user input and a representative 30-day window. Initial budget is 1% of mature accepted operations per class. If consumed, stop feature releases and investigate outstanding work, primary/queue pressure, partner lookups and metrics availability. No automatic blind republish.

Prometheus rules: mature good/total < .99 for 2m, unfinished age > deadline, metrics unavailable and absent API scraping. Low-volume cohorts (under 20) retain visible counts and age alerts; the ratio alert requires 20 to avoid presenting one fixture as a statistical availability result. See docs/sre-exercise.md and docs/publishing-reliability.md for recovery commands.

References: [Google SRE workbook](https://sre.google/workbook/implementing-slos/). This document describes proposed lab objectives; execution evidence is recorded separately.
