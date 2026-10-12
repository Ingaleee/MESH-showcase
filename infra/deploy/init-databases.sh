#!/bin/sh
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -v runtime_password="$RUNTIME_DATABASE_PASSWORD" <<'SQL'
CREATE ROLE mesh_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD :'runtime_password';
CREATE DATABASE mesh_queue OWNER mesh_owner;
CREATE DATABASE mesh_gateway OWNER mesh_owner;
SQL
