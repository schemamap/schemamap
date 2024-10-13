create or replace view schemamap.status as
select
  count(distinct schema_name) as schema_count,
  count(distinct (schema_name, table_name)) as table_count,
  count(1) as column_count,
  sum(case when is_pii then 1 else 0 end) as pii_count,
  sum(case when is_metadata then 1 else 0 end) as metadata_count,
  count(distinct case when is_schema_migration_table then table_name end) as schema_migration_table_count
from schemamap.smo;

comment on table schemamap.data_migrations is
  'Bookkeeping table of data migrations/imports that happened to this database.';
