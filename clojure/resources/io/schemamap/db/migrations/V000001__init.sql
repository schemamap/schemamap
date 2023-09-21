-- This section contains UDFs that are meant to be redefined by either the DBAs or by Schemamap Pro backend

-- Reasonable defaults, return type should be changed once supporting other types
-- Types:
-- - 1DB_WITH_TENANTS_TABLE_ID_FK
-- - 1DB_WITH_TENANTS_TABLE_NAME_FK
-- - 1DB_WITH_1SCHEMA_PER_TENANT
-- - DB_PER_TENANT
create or replace function schemamap.tenant_isolation()
returns table (type text, tenants_table_name text) as $$
  select '1DB_WITH_TENANTS_TABLE_ID_FK', 'public.tenants';
$$ language sql immutable;

create or replace function schemamap.list_tenants()
returns table (tenant_id text, tenant_short_name text, tenant_display_name text) as $$
  select
    null as tenant_id,
    null as tenant_short_name,
    null as tenant_display_name
  where 'TODO' is not null;
$$ language sql stable;
