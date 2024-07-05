#!/bin/bash
set -e

echo "Initializing Schemamap.io Postgres SDK for DB: $POSTGRES_DB"

schemamap init --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"

echo "Initialized Schemamap.io SDK 🎉"
