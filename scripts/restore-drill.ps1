$ErrorActionPreference = 'Stop'
docker compose stop dispatcher
if ($LASTEXITCODE -ne 0) { throw 'Cannot stop MESH dispatcher.' }
try {
  docker compose exec -e MESH_DRILL_DISPATCHER_STOPPED=true api bundle exec ruby script/restore_drill.rb
  if ($LASTEXITCODE -ne 0) { throw 'Restore drill failed.' }
} finally {
  docker compose start dispatcher
}
