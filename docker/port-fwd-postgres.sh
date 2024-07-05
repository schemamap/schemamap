#!/usr/bin/env bash

# Helper script to allow providing rathole client.toml files from outside of the container via exec:
# docker exec -i schemamap-postgres port-fwd-postgres < rathole-client.toml

read -rd "" stdin
echo "$stdin" > /schemamap/last-rathole-config.toml
exec schemamap up -f /schemamap/last-rathole-config.toml
