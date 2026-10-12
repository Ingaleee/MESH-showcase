#!/usr/bin/env bash
set -euo pipefail
[[ $(id -un) == mesh-runner ]] || { echo "Run as mesh-runner, not root." >&2; exit 1; }
[[ ${1:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Usage: mesh-register-runner OWNER/PRIVATE_REPO" >&2; exit 1; }
: "${GH_TOKEN:?Set a short-lived GitHub token with runner administration permission}"
repository=$1
[[ $(gh api "repos/$repository" --jq .private) == true ]] || { echo "This runner must attach to a private trusted repository." >&2; exit 1; }
cd /opt/actions-runner
[[ ! -f .runner ]] || { echo "Runner is already configured." >&2; exit 1; }
token=$(gh api --method POST "repos/$repository/actions/runners/registration-token" --jq .token)
trap 'unset token GH_TOKEN' EXIT
./config.sh --unattended --url "https://github.com/$repository" --token "$token" --name mesh-demo-linux --labels mesh-demo --work _work
unset token GH_TOKEN
echo "As the VM administrator: cd /opt/actions-runner; sudo ./svc.sh install mesh-runner; sudo ./svc.sh start"
echo "Runner registered. Confirm Online status in GitHub; no job execution is implied."
