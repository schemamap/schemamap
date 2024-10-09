create view schemamap.smo as
  select *
  from schemamap.schema_metadata_overview;

create or replace function schemamap.list_concepts()
returns table(concept_name text) as $$
  select
    substring(routine_name from 4) as concept_name
  from information_schema.routines
  where routine_schema = 'schemamap' and
        routine_name ilike 'is_%' and
        data_type = 'boolean';
$$ language sql stable;

create or replace function schemamap.redefine_smo_view_with_concepts()
returns void as $$
declare
  _concept_name text;
  _concept_columns text := '';
begin
  for _concept_name in select concept_name from schemamap.list_concepts() order by 1
  loop
    _concept_columns := _concept_columns || format(', schemamap.is_%I(smo) as is_%I', _concept_name, _concept_name);
  end loop;

  -- NOTE: do not depend on this view with other objects, use the schemamap.schema_metadata_overview matview instead.
  drop view if exists schemamap.smo;

  execute format('create or replace view schemamap.smo as
                  select smo.* %s
                  from schemamap.schema_metadata_overview smo',
    _concept_columns);
end;
$$ language plpgsql;

create or replace function schemamap.define_concept
(concept_name text, bool_select_sql text)
returns text as $concept$
begin
  execute format('create or replace function schemamap.is_%I(smo schemamap.schema_metadata_overview)
  returns bool as $def$
    %s
  $def$ language sql immutable strict parallel safe;', concept_name, bool_select_sql);
  raise notice '(Re-)defined schema concept for: %', $1;

  perform schemamap.redefine_smo_view_with_concepts();

  return concept_name;
end; $concept$ language plpgsql volatile security definer;

select schemamap.define_concept('pii', $$
  select
  lower(smo.column_name) ~*
  '^(email|first_name|last_name|full_name|middle_name|phone|telephone|mobile|address|street|city|state|zip|postal|ssn|social_security|dob|date_of_birth|birthdate|credit_card|ccn|card_number|passport|driver_license|license_number|national_id|tax_id|tin|ein|bank_account|account_number|routing_number|iban|bic|swift|personal_id|medicare|medicaid|health_insurance|policy_number|insurance_number|patient_id|member_id|user_id|username|login|password|secret|token|api_key|auth)'
$$);

select schemamap.define_concept('metadata', $$
  select smo.column_name in ('created_at', 'updated_at', 'version')
$$);

select schemamap.define_concept('schema_migration_table', $$
  select smo.table_name in
  (
  -- Rails / Supabase / Ecto / etc.
  'schema_migrations',
  -- Flyway
  'flyway_schema_history',
  -- Liquibase
  'databasechangelog',
  'databasechangeloglock',
  -- Django
  'django_migrations',
  -- SQLAlchemy
  'alembic_version',
  'alembic_version_table',
  -- Knex.js
  'knex_migrations',
  'knex_migrations_lock',
  -- Phinx (PHP)
  'phinxlog',
  -- TypeORM
  'typeorm_metadata',
  -- Goose (Go)
  'goose_db_version');
$$);

create or replace function schemamap.ignored_schemas()
returns table(nspname text) as $$
  values
    -- Postgres
   ('pg_catalog'), ('information_schema'),
   -- Citus
   ('columnar'), ('columnar_internal'),
   -- CockroachDB
   ('crdb_internal'),
   -- PostGIS
   ('tiger'),
   -- exclude ourselves to not pollute SMO with data migrations
   ('schemamap')
$$ language sql stable;

-- convenience views for consistency with smos
create view schemamap.tenants as select * from schemamap.list_tenants();
create view schemamap.mdes as select * from schemamap.list_mdes();
