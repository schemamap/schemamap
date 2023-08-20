create schema if not exists schemamap;

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

create table if not exists schemamap.column_mappings(
  id bigint primary key generated by default as identity,
  source_table text not null,
  source_column_name text not null,
  target_table text not null,
  target_column_name text not null,
  bidi_mapping_fn text not null references schemamap.bidi_mapping_fns,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0 check (version >= 0),
  unique (source_table, source_column_name, target_table, target_column_name)
);

create table if not exists schemamap.external_source_types (
  value text primary key,
  i18n jsonb,
  description text
);

insert into schemamap.external_source_types
(value, i18n, description)
values
('LOCAL_CSV', '{"name": {"en": "Local CSV"}}'::jsonb, 'Local comma separated values file, either a relative or absolute path'),
('LOCAL_SSV', '{"name": {"en": "Local SSV"}}'::jsonb, 'Local semicolon separated values (EU) file, either a relative or absolute path'),
('LOCAL_XLSX', '{"name": {"en": "Local XLSX"}}'::jsonb, 'Local xlsx file, either a relative or absolute path'),
('GOOGLE_SHEET', '{"name": {"en": "Google Sheet"}}'::jsonb, 'Google Sheet docs')
on conflict (value) do update set
  i18n = excluded.i18n,
  description = excluded.description;

create table if not exists schemamap.external_sources(
  id bigint primary key generated by default as identity,
  url text,
  sheet_id text,
  type text not null references schemamap.external_source_types,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 0 check (version >= 0),
  constraint sheet_id_or_url_must_be_present check (
    case when type = 'GOOGLE_SHEET' then
      sheet_id is not null
    else
      url is not null
    end)
);

select schemamap.add_common_triggers('schemamap.external_sources');

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
  select pp.oid, pg_catalog.pg_get_function_arguments(pp.oid), pg_catalog.pg_get_function_result(pp.oid), pl.lanname, pp.provolatile
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

  execute format('create or replace function schemamap.%I(%s) returns %s as $fn$ %s $fn$ language %s %s', $1, v_function_args, v_function_returns, new_body, v_function_lang, volatile_verbose);
  raise notice 'Updated schemamap UDF definition for %', $1;
end; $$ language plpgsql volatile;

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

create or replace function schemamap.verify_installation()
returns table(tenants_defined boolean,
              mdes_defined boolean,
              external_sources_defined boolean) as $$
  select
    exists(select 1 from schemamap.list_tenants() where tenant_id is not null) as tenants_defined,
    false as mdes_defined,
    false as external_sources_defined
$$ language sql stable;
