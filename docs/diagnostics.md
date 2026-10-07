# Диагностика showcase одной командой

```powershell
node scripts/diagnose.mjs
```

Команда проверяет frontend, DB readiness, session shape, состояние восьми showcase containers, queue snapshot и health локального integration simulator. Вывод — JSON без environment secrets, CSRF token, business messages и логов; nonzero означает проблему. Файлы сохраняются в MESH_EVIDENCE_DIR или showcase-final.

HTTP ограничен loopback адресами, пятью секундами и 16 KiB JSON; queue SQL имеет statement_timeout 1 секунду, процесс boot — 45 секунд. Docker inspection фильтруется exact Compose project. Скрипт не рестартует сервисы, не выполняет reconciliation, не вызывает внешнего провайдера и не принимает платежи. Healthy gateway означает только доступность simulator, не успешность денежной операции. Heartbeat не доказывает полезную работу каждого worker; failed rows показаны отдельно для расследования.

Для production demonstration:

```powershell
$env:MESH_DIAGNOSTIC_PROJECT = "mesh-showcase-release"
$env:MESH_DIAGNOSTIC_ORIGIN = "https://localhost:3243"
$env:NODE_EXTRA_CA_CERTS = "$PWD/.cache/deployment/root.crt"
node scripts/diagnose.mjs
```

Private CA применяется только к этому Node process; insecure TLS обхода нет. Docker socket access даёт широкий контроль над host — команда предназначена для доверенного оператора изолированного demo, не для произвольного внешнего запроса.
