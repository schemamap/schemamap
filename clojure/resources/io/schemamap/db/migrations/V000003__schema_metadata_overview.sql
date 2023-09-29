create or replace function schemamap.ignored_schemas()
returns table(nspname text) as $$
  values ('pg_catalog'), ('information_schema'), ('schemamap')
  -- not marking as immutable so a re-definition potentially read from the DB
$$ language sql stable;

create materialized view if not exists schemamap.schema_metadata_overview as
with ignored_schemas as (
  select nspname from schemamap.ignored_schemas()
),

base as (
  select
    n.nspname as schema_name,
    c.relname as table_name,
    c.relkind as object_type,
    obj_description(c.oid) as description
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r', 'v', 'm') and
        n.nspname not in (select nspname from ignored_schemas)
),

columns as (
  select
    n.nspname as schema_name,
    c.relname as table_name,
    a.attname as column_name,
    pg_catalog.format_type(a.atttypid, a.atttypmod) as data_type,
    a.attnotnull as not_null,
    pg_catalog.pg_get_expr(d.adbin, d.adrelid) as default_value,
    col_description(a.attrelid, a.attnum) as column_description,
    a.attnum as attnum
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  left join pg_attrdef e on e.oid = a.attrelid
  where a.attnum > 0 and
        not a.attisdropped and
        c.relkind in ('r', 'v', 'm') and
        n.nspname not in (select nspname from ignored_schemas)
),

constraints as (
  select
    n.nspname as schema_name,
    c.relname as table_name,
    pc.conname as constraint_name,
    pc.contype as constraint_type,
    pg_get_constraintdef(pc.oid) as constraint_definition,
    pc.conkey::int[] as constraint_keys,
    pc.confkey::int[] as foreign_keys
  from pg_constraint pc
  join pg_class c on c.oid = pc.confrelid or c.oid = pc.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname not in ('pg_catalog', 'information_schema')
),

indexes as (
  select
    n.nspname as schema_name,
    c.relname as table_name,
    i.relname as index_name,
    pi.indexrelid,
    pi.indisunique as is_unique,
    pi.indkey::int[] as index_keys
  from pg_index pi
  join pg_class c on c.oid = indrelid
  join pg_class i on i.oid = indexrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname not in (select nspname from ignored_schemas) and
        pi.indisprimary = false
)

select
  b.schema_name,
  b.table_name,
  b.object_type,
  b.description as table_description,
  c.column_name,
  c.data_type,
  c.not_null,
  c.default_value,
  c.column_description,
  jsonb_agg(distinct
    jsonb_build_object(
      'name', ct.constraint_name,
      'type', ct.constraint_type,
      'definition', ct.constraint_definition
  )) filter (where ct.constraint_name is not null and c.attnum = any(ct.constraint_keys)) as constraints,
  jsonb_agg(distinct
    jsonb_build_object(
     'name', i.index_name,
     'is_unique', i.is_unique
  )) filter (where i.index_name is not null and c.attnum = any(i.index_keys)) as indexes
from base b
join columns c on b.schema_name = c.schema_name and b.table_name = c.table_name
left join constraints ct on b.schema_name = ct.schema_name and b.table_name = ct.table_name and c.attnum = any(ct.constraint_keys)
left join indexes i on b.schema_name = i.schema_name and b.table_name = i.table_name and c.attnum = any(i.index_keys)
group by 1, 2, 3, 4, 5, 6, 7, 8, 9
order by b.schema_name, b.table_name, c.column_name;

create unique index if not exists schemamap_schema_metadata_overview_sname_tname_cname
  on schemamap.schema_metadata_overview (schema_name, table_name, column_name);

create or replace function schemamap.update_schema_metadata_overview(concurrently boolean default false)
returns void as $$
begin
  if $1 then
    refresh materialized view concurrently schemamap.schema_metadata_overview;
  else
    refresh materialized view schemamap.schema_metadata_overview;
  end if;
end; $$ language plpgsql security definer;

revoke all on function schemamap.update_schema_metadata_overview(boolean) from public;
