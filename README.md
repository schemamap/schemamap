# Schemamap.io

This repository contains the open-source SQL schema and SDKs of [Schemamap.io](https://schemamap.io).

## TLDR

| What you need      | System that infers it from your Postgres schema       |
|--------------------|-------------------------------------------------------|
| REST API           | [Postgrest](https://postgrest.org/en/stable/)         |
| GraphQL API        | [Hasura](https://hasura.io/), [Supabase](https://github.com/supabase/pg_graphql) |
| Table-based API    | :tada: **Schemamap.io** :tada:                            |

## Overview

Schemamap.io provides a common SQL and backend interface for your Postgres-based multi-tenant application, regardless of your framework.

Instead of maintaining CSV/Excel imports and exports by hand, generate them using industry-standard patterns via a rule engine.

As your schema evolves (new columns/tables) so do your table-based interfaces, along with import/export SQL scripts.

## Formats supported

- Free:
  - CSV
- Usage-based API integrations:
  - Google Sheets
- Work in Progress:
  - Excel (`.xls` and `.xlsx`)
  - Salesforce API

## Features

- **Database Migrations**: SQL scripts that add `schemamap` schema and roles to your DB.
- **Security**: Robust handling for application Postgres DB roles / RLS
  - [PoLP](https://en.wikipedia.org/wiki/Principle_of_least_privilege)
  - Multiple roles with incrementally more privileges
    - Schema read access
    - Read-only access (to the minimum subset of tables, for exporting data)
    - Write access (to the minimum subset of tables, to import data without writing application layer code)
  - Give access as much or as little, given your security & threat model.
  - Support tenant-scoped roles that guarantee safe access via row-level-security
- **Schema as a View**: To support analysis, schema metadata is collected into a materialized view.
  - Query and analyze your schema with simple SQL queries, get holistic view of anomalies/exceptions to the patterns in your DB.
  - Great for onboarding new developers without needing an ER diagram
  - Schedule refresh at your convenience by just calling a SQL function:
    - periodically, using [pg_cron](https://github.com/citusdata/pg_cron)
    - after SQL migrations
    - from application code
- **SSH Port-Forwarding**: Connect your local/Docker Postgres securely for a local-first developer experience.
  - Provide your SSH public key, and get a personalized connection/port, that only you can access.
  - No need to setup firewall rules/Ngrok/bastion hosts to try out the feature-set.
  - Use with local mock/seed data or with an empty DB.
  - Get setup/usage help interactively from the app, while coding along in your favorite SQL client/psql.

## SDKs Supported 🛠️

Integrate `schemamap` seamlessly with language-specific SDKs.

Currently supported:

- **[Bash](./bash)**
- **[Clojure](./clojure)**:
  [![Clojars Project](https://img.shields.io/clojars/v/io.schemamap/schemamap-clj.svg)](https://clojars.org/io.schemamap/schemamap-clj)

_Watch out for more languages coming soon! Have a request? [Open an issue](https://github.com/schemamap/schemamap/issues/new)._

## Developing

### First-time setup
1. Install direnv and hook into your shell: https://direnv.net/#basic-installation
2. Install the Nix package manager: https://github.com/DeterminateSystems/nix-installer#readme
3. Run `direnv allow` (will prompt you to install https://devenv.sh/getting-started/#2-install-cachix, from Step 2.)
4. To make sure the LFS files (db dumps) are present, run: `git lfs pull`

### Day-to-day operations
1. `process-compose` to bring up the development environment services
2. `ci-test` to run the integration test suite locally (shut down `process-compose` beforehand)
3. `devenv info` to see what packages and scripts are available

## Feedback and Contributions 👥
We'd love to hear from you! Whether it's a bug report, feature request, or general feedback - feel free to [raise an issue](https://github.com/schemamap/schemamap/issues/new).

## Security Policy

Security is at the core Schemamap.io.

If you discover any issue regarding security, please disclose the information responsibly by sending an email to security@schemamap.io and not by creating a GitHub issue.

We'll get back to you ASAP and work with you to confirm and plan a fix for the issue.

Please note that we do not currently offer a bug bounty program.

## License 📜
Copyright © 2023-2024 Schemamap.io Kft.

This project is distributed under the MIT License. For more details, refer to the [LICENSE](./LICENSE) file.
