# [Odoo](https://www.odoo.com/)

Showcasing how the SDK integration works with the most widely-used Postgres-based CRM.

## Demo

1. Run `just test`, see [justfile](./justfile) what it does
2. Visit http://localhost:8069/ and create your user & tenant
3. Run `schemamap up` to create TCP tunnel config @ app.schemamap.io
4. Use the UI to create data migrations!

## Postgres

You can connect to the DB via `just psql` as the application DB role.
