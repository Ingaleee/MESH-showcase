#!/usr/bin/env bash
set -euo pipefail
directory="$PWD/.cache/tools-linux"
mkdir -p "$directory"
fetch() {
  local url=$1 file=$2 sha=$3
  curl -fsSL --retry 2 "$url" -o "$file"
  printf '%s  %s\n' "$sha" "$file" | sha256sum --check --status
}
fetch https://get.helm.sh/helm-v4.3.0-linux-amd64.tar.gz "$directory/helm.tar.gz" 86584a54def73570558f66f5111cc53dfed56689637ae32c1201205d494f54fb
tar -xzf "$directory/helm.tar.gz" -C "$directory"
fetch https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz "$directory/actionlint.tar.gz" 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
tar -xzf "$directory/actionlint.tar.gz" -C "$directory"
fetch https://releases.hashicorp.com/terraform/1.16.5/terraform_1.16.5_linux_amd64.zip "$directory/terraform.zip" 2bc2fcfff033265c9e02ca0351f01794eb122f62a9b2a49a3294b9e49eaab5e4
unzip -oq "$directory/terraform.zip" -d "$directory"
echo "$directory" >> "$GITHUB_PATH"
echo "$directory/linux-amd64" >> "$GITHUB_PATH"
