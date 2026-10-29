#!/usr/bin/env bash
# Run by the postgres image on the first start of an empty data folder
# (docker-entrypoint-initdb.d, see compose.yaml): the datyx database and
# its owner, and OpenMetadata's database and user, as its own
# postgres-script.sql makes them. Passwords come from the environment.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" \
  --set datyx_password="${DATYX_DB_PASSWORD:-datyx}" \
  --set openmetadata_password="${OPENMETADATA_DB_PASSWORD:-openmetadata_password}" <<'SQL'
CREATE USER datyx WITH PASSWORD :'datyx_password';
CREATE DATABASE datyx OWNER datyx;
CREATE USER openmetadata_user WITH PASSWORD :'openmetadata_password';
CREATE DATABASE openmetadata_db OWNER openmetadata_user;
SQL
