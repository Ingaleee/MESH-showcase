# Security review — 8 октября 2026

Строгий HIGH/CRITICAL gate для перечисленных текущих runtime artifacts прошёл. Политика включает unfixed findings; CVE allowlist/ignore-unfixed не включены. Результат относится к exact digests и времени scan, не ко всем будущим образам или возможным уязвимостям.

[Текущий hosted release](https://github.com/Ingaleee/MESH-showcase/actions/runs/37834690626) и [deployment](https://github.com/Ingaleee/MESH-showcase/actions/runs/37837289487) прошли: scan пяти exact registry digests, verified signature/source/workflow и negative wrong-revision control. [Актуальный каталог](evidence/acceptance-oct08/README.md) сохраняет отчёты; детали allowlists и trust boundaries — в [threat-model.md](threat-model.md).

## Историческое устранение находок

[Старый expanded report](evidence/publishing-security/image-security.json) сохранил application и инфраструктурные findings. Package applicability review для прежних Debian binaries с первичными источниками сохранена [отдельно](evidence/publishing-security/applicability.json). Она не использовалась для ослабления gate.

| Изменение                                                                                              | Проверка                                                                                 |
| ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| Ruby/Node production runtime на pinned Alpine 3.23 bases, runtime updates, unused npm/Corepack removed | Native Ruby suite 118/0; полный browser 13/13, HTTPS business/file workflow              |
| PostgreSQL 18.6: актуальные Alpine packages, unused gosu removed; запуск postgres user                 | Existing own volumes migrated normally; role/grants/business probe                       |
| ClamAV: patched openssl/pcre2 и related packages; signature initialization сохранена                   | Реальные clean file/package scans, quarantined failures не объявляются success           |
| Grafana 13.2.3: только нужный официальный Prometheus plugin 13.2.3, unused datasource binaries removed | Real dashboard/PromQL browser check; auto-download/update disabled для read-only runtime |
| Alertmanager 0.34.1: pinned upstream source/UI archives, Go 1.27.1, узкий gRPC 1.83.1 → 1.83.2 rebuild | Настоящие firing/resolved receipts после обновления; patched version label               |

Alertmanager — временный fork сборки, не новый официальный upstream release. У него есть стоимость сопровождения: нужно пересматривать patch и возвращаться к официальному исправленному образу после проверки. Origin archive/checksum/version labels зафиксированы в Dockerfile; build dependency разрешение всё ещё требует network. Grafana plugin version зафиксирована, signature проверяется Grafana; builder скачивает официальный package.

[Последний nine-image scan](evidence/publishing-security-complete/image-security.json): API, web, partner, PostgreSQL, ClamAV, Caddy, Prometheus, Grafana, Alertmanager — у каждого 0 HIGH/CRITICAL entries. Он записан после финальной сборки demo, включая bounded history UI. [Пятикомпонентный production release](evidence/publishing-release-security-current/image-security.json) также прошёл gate и [настоящий HTTPS business/file workflow + exit-42 rollback](evidence/publishing-release-current/runtime-and-rollback.json).

Эти inventories имеют собственные timestamps и exact IDs. Production rollback выполнен до небольшой финальной CSS-правки списка и повторных Compose rebuild metadata; его references не подменяются последним nine-image scan. API в production report включает stateless signed callback и отформатированный Ruby CLI. Исторические красные и прежние зелёные reports сохранены отдельно.

Development Ruby compiler image и builder stages не включены в approved production runtime scope. Алгоритмические ошибки, неизвестные CVE, runtime configuration, uploaded executable safety и external partner vulnerabilities Trivy не доказывает.

## Связь scan и deployment

V2 manifest содержит API, web, PostgreSQL, ClamAV и Caddy. Compose использует эти references; smoke сверяет фактически запущенные images, private ports и runtime role. GitHub release выполняет build/scan этого inventory до публикации manifest; deploy job получает artifact только от успешного release workflow на main, выбирает exact source commit и проверяет подписанное происхождение. Actual successful runs указаны выше.

```powershell
node scripts/check-images.mjs .cache/deployment/publishing-current-v2.json
```

Scanner pinned по digest, raw reports сохраняются и при nonzero. Local loopback deployment предназначен для runtime/rollback exercise; команда deploy сама scan не вызывает. Перед внешним продвижением нужен scan exact выбранного manifest и verified remote provenance. Local source hash с revision=null не является подписью.

## Секреты и HTTP

Partner/metrics/alert credentials генерируются отдельно и сохраняются в ignored local env. Пустой token не допускается в Compose partner; metrics config также требует подготовку. HTTP integration имеет approved origins, HTTPS default, VERIFY_PEER, custom CA option, bounded requests/response/JSON/deadline, no redirects/implicit retry/proxy inheritance. HTTP lab allowance явный и ограничен configured simulator origin. Simulator failpoint не исполняет uploaded HTML.

```powershell
node scripts/check-secrets.mjs
```

Gitleaks проверил publishable source snapshot: clean report и найденный random api_key canary. Ignored local runtime files остаются вне publishable scope; текущий CI также сканирует всю fetched Git history. Архивные reports ниже относятся к более раннему source-only scan. Три narrow allowlists различают SHA verification hashes, synthetic blob keys и exact report command UUIDs; отдельное правило разрешает только SHA-1 Digest fields в перечисленных exact Trivy Grafana inventories, которые совпадали с legacy Sourcegraph-token pattern. Общие credential-shaped строки остаются запрещены; canary это проверил.

[Reports](evidence/publishing-quality/gitleaks.json), [canary](evidence/publishing-quality/gitleaks-canary.json), [Brakeman](evidence/publishing-quality/brakeman.json), [npm](evidence/publishing-quality/npm-audit.json). Bundler-audit report содержит download context и JSON results=[].

## Оставшаяся эксплуатационная работа

GHCR attestations/signature verification выполнены. Credential rotation regression проверяет приложение через double, но independent secret manager/custody, offsite retention и hardened multi-host deployment ещё требуют отдельной приёмки. Zero findings сегодня не заменяет повторный scan при security updates и release.
