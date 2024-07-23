#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# default to root folder when running in CI/outside of devenv
: "${DEVENV_ROOT:=$PARENT_DIR}"

printf -- '-- Generated from schemamap.dev\n' > "$DEVENV_ROOT/rust/create_schemamap_schema.sql"
printf 'SET search_path TO schemamap;' >> "$DEVENV_ROOT/rust/create_schemamap_schema.sql"

for file in "$DEVENV_ROOT/sql/"*; do
  { printf '\n-- %s\n' "$(basename "$file")"
    cat "$file"
  } >> "$DEVENV_ROOT/rust/create_schemamap_schema.sql"
done
