#!/usr/bin/env bash

echo 'Downloading Schemamap.io migration files...'
wget -qN schemamap.dev/create_schemamap_users.sql schemamap.dev/create_schemamap_schema.sql schemamap.dev/grant_schemamap_usage.sql

export PGDATABASE="${PGDATABASE:-postgres}"
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"

echo
echo 'Trying connecting to your Postgres, based on these env vars:'
env | grep '^PG'

if ! psql -c 'SELECT 1;' > /dev/null 2>&1; then
    echo "Failed to connect to database. Please export the proper environment variables and run the install script again."
    echo "Example:"
    echo "export PGUSER=$(whoami)"
    exit 1
fi

echo
echo "Creating Schemamap.io users in $PGDATABASE"
echo "grant connect, create on database $PGDATABASE to schemamap;" >> ./create_schemamap_users.sql
psql -1 -f ./create_schemamap_users.sql

echo
echo "Installing 'schemamap' schema to $PGDATABASE"
export PGUSER=schemamap
export PGPASSWORD=schemamap
psql -1 -f ./create_schemamap_schema.sql

echo
echo "Granting usage rights of schemamap to all roles"
psql -1 -f ./grant_schemamap_usage.sql
