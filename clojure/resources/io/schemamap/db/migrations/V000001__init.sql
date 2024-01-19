create schema if not exists schemamap;

create or replace function schemamap.list_tenants()
returns table (
  tenant_id text,
  tenant_short_name text,
  tenant_display_name text,
  tenant_locale text,
  tenant_data jsonb) as $$
  select
    null as tenant_id,
    null as tenant_short_name,
    null as tenant_display_name,
    null as tenant_locale,
    null::jsonb as tenant_data
  where 'TODO' is null;
$$ language sql stable;

create or replace function schemamap.trggr_set_update_common_fields()
returns trigger as $$
begin
  -- allow setting updated_at explicitly
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at = now();
  end if;
  new.version = old.version + 1;

  return new;
end; $$ language plpgsql stable;

create or replace function schemamap.trggr_optimistic_update_guard()
returns trigger as $$
begin
  if new.version != old.version + 1 then
    raise exception 'Optimistic update failed' using hint = 'try again';
  end if;

  -- decrement new version so the trggr_set_update_common_fields trigger doesn't bump it twice
  new.version = old.version;

  return new;
end; $$ language plpgsql stable;

create or replace function schemamap.add_common_triggers(table_name text)
returns void as $$
begin
  execute format (
    'drop trigger if exists aaa_sm_io_optimistic_locking_update_guard on %s', table_name
  );

  execute format('
    create trigger aaa_sm_io_optimistic_locking_update_guard
    before update of version on %s for each row
    execute procedure schemamap.trggr_optimistic_update_guard();
  ', table_name);

  execute format (
    'drop trigger if exists aab_sm_io_maintain_update_fields on %s;', table_name
  );

  execute format('
  create trigger aab_sm_io_maintain_update_fields
  before update on %s for each row
  execute procedure schemamap.trggr_set_update_common_fields();
  ', table_name);
end; $$ language plpgsql volatile;

create table if not exists schemamap.table_metadata (
  id bigint primary key generated by default as identity,
  table_name text not null unique,
  natural_key_constraint_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0 check (version >= 0)
);

comment on table schemamap.table_metadata is 'Categorizes tables to be mapped from/to.';
comment on column schemamap.table_metadata.table_name is 'The fully qualified table name as described, as per search_path.';
comment on column schemamap.table_metadata.natural_key_constraint_name is 'The unique constraint name that is used to support bidirectional mapping.';

select schemamap.add_common_triggers('schemamap.table_metadata');

create or replace function schemamap.trim_str(text)
returns text as $$
  select trim($1);
$$ language sql immutable strict parallel safe;

create or replace function schemamap.identity(anyelement)
returns anyelement as $$
  select $1;
$$ language sql immutable strict parallel safe;

create or replace function schemamap.trim_str(text)
returns text as $$
  select trim($1);
$$ language sql immutable strict parallel safe;

-- TODO: handle escapes
create or replace function schemamap.split_comma_sep_str(text)
returns text[] as $$
  select string_to_array($1, ',');
$$ language sql immutable strict parallel safe;

create or replace function schemamap.join_array_to_comma_sep_str(anyarray)
returns text as $$
  select array_to_string($1, ',');
$$ language sql immutable strict parallel safe;

create table if not exists schemamap.bidi_mapping_fns (
  name text primary key,
  i18n jsonb not null,
  forward_fn_name text not null,
  backward_fn_name text not null,
  input_type text not null,
  exact boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0 check (version >= 0)
);

select schemamap.add_common_triggers('schemamap.bidi_mapping_fns');

insert into schemamap.bidi_mapping_fns
(name, i18n, forward_fn_name, backward_fn_name, input_type, exact)
values
('trim_str', '{"name": {"en": "Trim"}}'::jsonb, 'trim_str', 'identity', 'text', false),
('identity', '{"name": {"en": "Identity"}}'::jsonb, 'identity', 'identity', 'anyelement', true),
('split_comma_array', '{"name": {"en": "Split Commas To Array"}}'::jsonb, 'split_comma_sep_str', 'join_array_to_comma_sep_str', 'text', true)
on conflict (name) do update set
  i18n = excluded.i18n,
  forward_fn_name = excluded.forward_fn_name,
  backward_fn_name = excluded.backward_fn_name,
  input_type = excluded.input_type,
  exact = excluded.exact;

create or replace function schemamap.get_function_definition(function_name text)
returns text as $$
  select pg_catalog.pg_get_functiondef(pp.oid)
  from pg_proc pp
  join pg_namespace pn on pn.oid = pp.pronamespace
  where
    pn.nspname = 'schemamap' and
    pp.proname = function_name;
$$ language sql stable;

create or replace function schemamap.update_function_definition
(function_name text, new_body text)
returns void as $$
declare
  v_function_oid oid;
  v_function_args text;
  v_function_returns text;
  v_function_lang text;
  v_function_volatile text;
  volatile_verbose text;
begin
  select pp.oid,
         pg_catalog.pg_get_function_arguments(pp.oid),
         pg_catalog.pg_get_function_result(pp.oid),
         pl.lanname,
         pp.provolatile
  into v_function_oid, v_function_args, v_function_returns, v_function_lang, v_function_volatile
  from pg_proc pp
  join pg_namespace pn on pn.oid = pp.pronamespace
  join pg_language pl on pl.oid = pp.prolang
  where pn.nspname = 'schemamap' and pp.proname = $1;

  volatile_verbose := case
    when v_function_volatile = 's' then 'stable'
    when v_function_volatile = 'i' then 'immutable' end;

  if v_function_volatile = 'v' then
    raise exception 'function %.% is volatile. update not allowed.', 'schemamap', $2;
  end if;

  execute format('create or replace function schemamap.%I(%s) returns %s as $fn$ %s $fn$ language %s %s',
  $1, v_function_args, v_function_returns, new_body, v_function_lang, volatile_verbose);
  raise notice 'Updated schemamap UDF definition for %', $1;
end; $$ language plpgsql volatile security definer;

-- https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY
revoke all on function schemamap.update_function_definition(text, text) from public;

create or replace function schemamap.define_master_data_entity
(mde_name text, new_body text)
returns void as $$
begin
  execute format('create or replace view schemamap.mde_%I as %s', $1, $2);
  raise notice '(Re-)defined schemamap MDE definition for %', $1;
end; $$ language plpgsql volatile security definer;


-- https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY
revoke all on function schemamap.define_master_data_entity(text, text) from public;

create or replace function schemamap.list_mdes()
returns table(mde_name text) as $$
  select substring(table_name from 5) as mde_name
  from information_schema.views
  where table_schema = 'schemamap' and table_name like 'mde\_%' escape '\';
$$ language sql stable;

create or replace function schemamap.master_date_entity_candidates()
returns
  table(schema_name text,
        table_name text,
        approx_rows bigint,
        foreign_key_count bigint,
        probability_master_data real)
as $$
with tablestats as (
    select
        ns.nspname as schema,
        cls.relname as tablename,
        cls.reltuples::bigint as approx_rows,
        count(con.*) as foreign_key_count
    from pg_catalog.pg_class cls
    join pg_catalog.pg_namespace ns on ns.oid = cls.relnamespace
    left join pg_catalog.pg_constraint con on con.confrelid = cls.oid
    where cls.relkind = 'r' and ns.nspname not in (select nspname from schemamap.ignored_schemas())
    group by 1, 2, 3
), minmax as (
    select
        min(approx_rows) as min_rows,
        max(approx_rows) as max_rows,
        min(foreign_key_count) as min_fk,
        max(foreign_key_count) as max_fk
    from tablestats
)
select
    schema as schema_name,
    tablename as table_name,
    approx_rows,
    foreign_key_count::bigint as foreign_key_count,
    coalesce(
        case
            when max_fk = min_fk and max_fk = 0 then
                (max_rows - approx_rows)::real / nullif((max_rows - min_rows), 0)::real
            else
                (0.5 * ((max_rows - approx_rows)::real / nullif((max_rows - min_rows), 0)::real)) +
                (0.5 * ((foreign_key_count - min_fk)::real / nullif((max_fk - min_fk), 0)::real))
        end,
        0
    ) as probability_master_data
from tablestats, minmax
order by probability_master_data desc
$$ language sql stable;

create table schemamap.i18n_stored (
  value jsonb not null
);

insert into schemamap.i18n_stored values ('{}'::jsonb);

revoke insert on schemamap.i18n_stored from public;

create or replace function schemamap.i18n()
returns jsonb as $$
  select value from schemamap.i18n_stored
$$ language sql stable;


create or replace function schemamap.update_i18n (new_i18n_value jsonb)
returns void as $$
  update schemamap.i18n_stored set value = new_i18n_value;
$$ language sql security definer;

revoke all on function schemamap.update_i18n(jsonb) from public;

create or replace function schemamap.ignored_schemas()
returns table(nspname text) as $$
  values ('pg_catalog'), ('information_schema'), ('schemamap')
  -- not marking as immutable so a re-definition can potentially read from the DB
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
  where n.nspname not in (select nspname from ignored_schemas)
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
  c.column_name,
  b.object_type,
  b.description as table_description,
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
order by 1, 2, 3;

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

create or replace function schemamap.verify_installation()
returns table(tenants_defined boolean, mdes_defined boolean) as $$
  select
    exists(select 1 from schemamap.list_tenants() where tenant_id is not null) as tenants_defined,
    exists(select 1 from schemamap.list_mdes() where mde_name is not null) as mdes_defined
$$ language sql stable;
