#!/usr/bin/env bash
# Run by the postgres image on the first start of an empty data folder
# (docker-entrypoint-initdb.d, see compose.yaml): the healthhub database
# and its owner. The password comes from the environment. The API makes
# its own tables (healthhub_api/lib/db.dart).
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" \
  --set healthhub_password="${HEALTHHUB_DB_PASSWORD:-healthhub}" <<'SQL'
CREATE USER healthhub WITH PASSWORD :'healthhub_password';
CREATE DATABASE healthhub OWNER healthhub;
SQL
