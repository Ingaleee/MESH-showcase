#!/usr/bin/env bash
set -euo pipefail
state=${MESH_DEPLOYMENT_STATE:-"$PWD/.cache/deployment"}
mkdir -p "$state"
# Children inherit fd 9: killing Node does not release the lock while Docker is still running.
exec 9>"$state/deploy.lock"
flock --exclusive --nonblock 9 || { echo "Another deployment owns the OS lock." >&2; exit 73; }
export MESH_RELEASE_LOCK_FD=9
exec node scripts/release.mjs "$@"
