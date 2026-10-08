# Kubernetes: что проверяется и что нужно для живого запуска

Chart deploys API (2 replicas), frontend, worker и dispatcher. Образы только с digest. PostgreSQL/queue/gateway/ClamAV, runtime/migration Secrets, TLS и общий files PVC — явно внешние зависимости. Chart не притворяется, что установка Deployment создаёт PostgreSQL HA.

Render-check:
```powershell
.cache/tools/helm/windows-amd64/helm.exe lint infra/helm/mesh --set images.api=ghcr.io/example/mesh-api@sha256:<64 hex> --set images.web=ghcr.io/example/mesh-web@sha256:<64 hex> --set files.existingClaim=mesh-files
```

Runtime Secret содержит DATABASE_URL, QUEUE_DATABASE_URL, SECRET_KEY_BASE, MESH_METRICS_TOKEN, MESH_GATEWAY_SECRET, MESH_WEBHOOK_SECRET. Migration Secret — те же ключи, но DB URLs владельца. Private registry требует заранее созданных credentials/imagePullSecrets на runtime/default service accounts; публичные образы не требуют credentials. Секреты не входят в values/evidence.

PVC нужен ReadWriteMany для нескольких nodes или ReadWriteOnce при сознательном размещении всех file consumers на одном node. Deployment strategy maxSurge требует дополнительной памяти. Topology spread включается только с подходящим storage. Local single-host cluster не доказывает физическую HA.

Миграция — отдельный контролируемый Job. Сначала применить ServiceAccount/ConfigMap и внешние зависимости, затем migration Job, дождаться Complete и применить grants для runtime. Только после этого rollout Deployments. Chart по умолчанию не запускает Job при обычном upgrade; автоматический hook не используется, чтобы первый install не зависел от ещё не созданного ConfigMap. Для следующего отдельного Job выбрать новое release/name, чтобы не обновлять immutable Job template.

```sh
kubectl rollout status deployment/mesh-api --timeout=180s
kubectl rollout undo deployment/mesh-api
kubectl rollout status deployment/mesh-api --timeout=180s
```

После undo API нужно откатить согласованный frontend image/version и выполнить smoke. Kubernetes undo не откатывает миграции, workers или DB. Для настоящего выпуска использовать единый release manifest.

Startup ждёт boot. Readiness API проверяет DB/queue. Liveness /up проверяет процесс без DB, чтобы отказ зависимости не создавал restart storm. Worker/dispatcher не получают фиктивную HTTP probe; их exit управляет restart, очередь/heartbeat контролируют metrics и alerts. PDB относится к добровольным disruptions, а rolling update управляется Deployment strategy.

NetworkPolicy опциональна до выбора CNI. При включении разрешены ingress controller, DNS и namespace-local dependency pods с label mesh.showcase/dependency=true на нужных портах. Внешний DB/OTLP требует явного дополнительного egress policy. Enforcement проверяется реальным curl/connection denial в выбранном кластере; render не подтверждает enforcement.
