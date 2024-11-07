<div align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/images/schemamap_logo_light.png">
  <img height="150" src=".github/images/schemamap_logo_dark.png">
</picture>
</div>
<p align="center">
Instant batch data import for Postgres
</p>
<p align="center">
  <a href="https://schemamap.io/demo"><img src="https://img.shields.io/badge/Try the Demo!-blue?logoColor=purple"/></a>
  <a href="mailto:krisz@schemamap.io"><img src="https://img.shields.io/badge/Email%20the%20Founder-purple" /></a>
  <a href="https://github.com/schemamap/schemamap/blob/main/LICENSE"><img src="https://img.shields.io/github/license/schemamap/schemamap"/></a>
  <a href="https://github.com/sourcebot-dev/sourcebot/actions/workflows/ghcr-publish.yml"><img src="https://img.shields.io/github/actions/workflow/status/schemamap/schemamap/push-tag.yml"/><a>
  <a href="https://github.com/schemamap/schemamap/stargazers"><img src="https://img.shields.io/github/stars/schemamap/schemamap" /></a>
</p>

<p align="center">
    <a href="https://discord.schemamap.io"><img src="https://dcbadge.limes.pink/api/server/https://discord.gg/P3UzxNusbA?style=flat"/></a>
</p>

## Schemamap is a data ingestion platform for your Postgres-based product

### Customer onboarding & success

- Import correct customer data into hundreds of **Production DB** tables in _seconds_, not weeks
- Reduce Time To Value by 50% for long onboarding flows, reducing churn
- Integrations built for your product automatically, maintained as your application evolves
- Automatic multi-tenant dashboards for customer data health and onboarding success, inferred from your DB
- Eliminate tedious one-by-one configuring of master data after go-lives, sync data safely from Pre-Prod to Prod

### Developer productivity

- Test code against anonymized Production data in lower-level environments
- Easily reproduce bugs locally by subsetted Postgres -> Postgres syncing
- Merge data between Postgres DB branches on platforms like Supabase and Neon
- Create DB snapshots locally for easy switching between Git branches while keeping data intact, syncing data between snapshots

### Data governance

- Solve GDPR, SOC2, DPDP, FERPA, HIPAA compliance with database-level controls and eliminating privacy risk
- Schema Metadata as Data allows DB -> Backend -> Frontend sharing of constraints/validation logic for consistent UX

## Get started for free

Install the Postgres-level SDK into your local database:

```
brew install schemamap/tap/schemamap
export DATABASE_URI="postgres://postgres:postgres@localhost:5432/postgres"
schemamap init
```

## Usage

See your DB status immedieatly:

```
schemamap status
```

See individual column metadata as JSON:

```
schemamap status -a | jq '.'
```

See SDK integration improvements, for multi-tenancy:

```
schemamap doctor
```

Connect to the Schemamap.io Cloud to start receiving batch data migrations:

```
schemamap up
```

## Philosophy

Our mission is to increase the number of successful Postgres-based products in the world.
To do that, we build data import tooling that help you get the correct data you need into your product.

Postgres has one of the strongest Data Definition Language in the RDBMS world, paralleling the power of dependent type systems.
Our belief is that this rich metadata has been underused by existing tooling and developers.

Instant API tools like PostgREST and Hasura were the correct first steps to allow easy data ingestion, one record at a time.
They fall short though on large-scale data operations, that span more than a handful of tables or thousands of records.
This requires a fundamentally different approach, which is asynchronous, requires careful handling of networking, I/O and most importantly data security.

When integrating a data source, manually specifying transformation & mapping decisions on thousands of columns is unfeasible and tedious.

Our claim is that by constraining our Postgres databases more (therefore defining what is "correct") we can use logic programming and constraint-solving methods to automatically ingest data from any source.

This unlocks a new level of productivity that allows small teams to build even more ambitious applications than ever before.

Schemamap gives you every tool you need to understand your product, develop and test it confidently, and release changes without being slowed down by domain complexity.
