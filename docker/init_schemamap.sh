#!/bin/bash
set -e

echo "Initializing Schemamap.io Postgres SDK for DB: $POSTGRES_DB"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -f /schemamap/create_schemamap_users.sql \
  -c "grant connect, create on database $POSTGRES_DB to schemamap;" \
  -c "set role schemamap;" \
  -f /schemamap/create_schemamap_schema.sql \
  -f /schemamap/grant_schemamap_usage.sql

echo "Initialized Schemamap.io SDK 🎉"
