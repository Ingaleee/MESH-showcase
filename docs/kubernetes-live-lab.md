Текущий hosted registry exercise: [run 37837294244](https://github.com/Ingaleee/MESH-showcase/actions/runs/37837294244) — success. Выполнены current Alpine digests, Terraform drift, migration ordering, CNI controls, worker/DB recovery и failed-upgrade rollback. [Summary](evidence/acceptance-oct08/hosted/kubernetes/summary.json). Ниже сохранён прежний local exercise со своим DB placement и image scope.

# Живые Kubernetes и Terraform упражнения

8 октября 2026 выполнены на отдельном k3d-mesh-showcase: k3d 5.9.0, K3s v1.35.5+k3s1, один server, containerd 2.2.3-k3s1. Cluster сейчас остановлен для экономии памяти, данные и state сохранены. Основной MESH продолжал отвечать на localhost:3100.

| Проверка        | Наблюдение                                                                                                                      | Evidence                                                                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Terraform apply | Созданы namespace, quota, LimitRange                                                                                            | [Apply/drift summary](evidence/publishing-kubernetes/terraform-summary.json)                                                                |
| Terraform drift | requests.cpu вручную 4 → 3; plan exit 2; apply исправил; final plan exit 0                                                      | [Drift plan](evidence/publishing-kubernetes/terraform-drift.txt), [clean plan](evidence/publishing-kubernetes/terraform-repaired-clean.txt) |
| Helm rollback   | Неправильный web image отклонён; предыдущий web восстановлен; revision 3 deployed                                               | [Summary](evidence/publishing-kubernetes/helm-summary.json), [history](evidence/publishing-kubernetes/helm-history.json)                    |
| NetworkPolicy   | Approved API HTTP 200/DB TCP connected; untrusted ingress denied; selected pod partner egress denied; positive control HTTP 200 | [Real CNI probes](evidence/publishing-kubernetes/networkpolicy.json)                                                                        |
| Worker recovery | 50 synthetic events, один effect на event после scale 0 → 1                                                                     | [Recovery](evidence/publishing-kubernetes/recovery.json)                                                                                    |
| DB outage       | ready 503, liveness 200; два API pod UID сохранились, restart=0; после DB start ready снова True                                | [Recovery](evidence/publishing-kubernetes/recovery.json)                                                                                    |

Проверки rollout здесь использовали прежние Debian application images, указанные в pods/values reports. Более поздний Alpine security scan и native RSpec — отдельные доказательства. Нельзя выдавать этот rollout за проверку последних Alpine digest.

## Разделение данных

Cluster подключён только к mesh-showcase_default. Dedicated logical DB: mesh_kubernetes / mesh_kubernetes_queue, отдельная restricted runtime role. Secret — ignored .cache/kubernetes/runtime.env, kubeconfig/state — .cache/kubernetes. Не используется глобальный current-context. Files — отдельный mesh-files PVC local-path/RWO. Terraform namespace имеет prevent_destroy.

NetworkPolicy разрешает конкретный внешний PostgreSQL /32:5432, DNS и перечисленные pod dependencies; broad wildcard egress не добавлен. Port-forward не считается доказательством network isolation: probes шли из реальных pods.

## Повтор на подготовленном Windows host

Не запускать одновременно с тяжёлым production-release. Для DB-outage drill остановите preview consumers своего showcase: упражнение намеренно останавливает mesh-showcase-db-1. Основной продукт использует другую DB.

```powershell
.cache/tools/k3d/k3d.exe cluster start mesh-showcase
$env:KUBECONFIG = (Join-Path $PWD '.cache/kubernetes/config')
.cache/tools/kubectl/kubectl.exe --context k3d-mesh-showcase -n mesh-showcase get pods
.cache/tools/terraform/terraform.exe -chdir=infra/terraform/namespace plan -var-file="../../../.cache/kubernetes/terraform.tfvars.json"
node scripts/check-kubernetes-network.mjs
node scripts/check-kubernetes-recovery.mjs
.cache/tools/k3d/k3d.exe cluster stop mesh-showcase
```

Network probe требует запущенного собственного partner simulator для positive control. Recovery script восстанавливает worker/database в finally. После упражнений возвращайте preview через npm run demo. Scripts привязаны к этому local context и путям Windows tools; это не универсальный cloud installer.

Первичное создание стенда включало cluster create на network mesh-showcase_default с 3500 MB cap, импорт immutable images, prepare-kubernetes-data.mjs, миграции от owner, runtime grants, Terraform apply, PVC/Secret и Helm install. Actual values, tool versions и raw reports сохранены; это отдельная процедура подготовки, не одна команда bootstrap для произвольного host.

## Что этот стенд не доказывает

Два API replicas на одном node не создают HA. RWO local-path зависит от node, DB вне cluster остаётся одиночной. PDB не защищает от потери host. Ansible apply/idempotence и настоящий GitHub runner здесь не выполнены; для этого нужна отдельная Ubuntu VM и отложенный пользователем repository. Фиксированный inventory IP и local image import нельзя переносить в cloud без изменения addressing/registry/storage.
