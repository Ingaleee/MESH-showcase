# Доверенная VM, Ansible и Terraform

GitHub repo и отдельной Ubuntu VM пока нет. Конфигурации подготовлены для этих целей; запись «проверен runner» появляется только после Online и реального job.

Runner принимает код с правами Docker, что фактически даёт власть над VM. Поэтому VM отдельная, без секретов/томов основного продукта; registration helper проверяет private repository. Для публичного портфолио безопасный вариант — hosted verification/build и отдельная private deployment repository. Публичный self-hosted runner нельзя защитить одним workflow if. [Рекомендация GitHub](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners).

Ansible controller — Linux/WSL или контейнер. SSH host keys проверяются; inventory намеренно пустой до выбора VM. Ubuntu 22.04/24.04 x64, минимум 6 GiB RAM/4 CPU/40 GiB disk для последовательной демонстрации. На текущем Windows host память ограничена: VM не создана и Windows features не переключались.

```sh
cd infra/ansible
ansible-playbook runner.yml --syntax-check
ansible-playbook -i inventory.local.ini runner.yml --check --diff
ansible-playbook -i inventory.local.ini runner.yml
ansible-playbook -i inventory.local.ini runner.yml
```

Второе применение должно быть changed=0 вне ожидаемой загрузки apt metadata/нового package version. Роли не регистрируют runner и не генерируют GitHub token автоматически. Pinned archives проверяются SHA256; update установленного runner требует остановить service и осознанно обновить его, либо allow auto-update самого runner. Docker packages устанавливаются из signed official apt source; это не lock всего OS snapshot. [Установка Docker](https://docs.docker.com/engine/install/ubuntu/).

После создания repo запускается helper как mesh-runner с краткоживущим GH_TOKEN, затем service; secret никогда не пишется в inventory или evidence. Deployment secrets создаются Node-командой с MESH_DEPLOYMENT_STATE=/var/lib/mesh-showcase/deployment. Root только подготавливает host; runner служба работает отдельным пользователем.

Terraform имеет конкретный узкий scope: namespace showcase, Pod Security labels, quota, LimitRange выбранного Kubernetes context. Helm управляет приложением. Terraform не выдумывает cloud account и не создаёт платные VM.

```sh
cd infra/terraform/namespace
terraform init
terraform validate
terraform test
terraform plan -var='kube_context=kind-mesh-showcase' -out=plan
terraform apply plan
terraform plan -var='kube_context=kind-mesh-showcase'
```

plan/apply и drift требуют настоящего выбранного кластера. Mock tests проверяют план конфигурации, не API-server/CNI/storage. State/plan и .terraform ignored; credentials читаются из kubeconfig, не сохраняются в tfvars. Для совместной работы нужен remote backend с locking/encryption; local state годится для единственного локального оператора. prevent_destroy защищает namespace от случайного destroy; снятие защиты перед удалением требует отдельного решения.

Runner role явно устанавливает ICU/SSL/Kerberos/zlib/lttng зависимости для выбранной Ubuntu версии по [официальному dependency helper pinned runner](https://github.com/actions/runner/blob/v2.338.0/src/Misc/layoutbin/installdependencies.sh). Syntax check не подтверждает доступность apt packages, совместимость host или реальный service start; это проверяется при apply на VM.
