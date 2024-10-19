drop view if exists schemamap.status;

select schemamap.define_concept('primary_key', $$
  select exists (
    select 1
    from jsonb_array_elements(smo.constraints) as c
    where (c->>'type') = 'p'
  );
$$);

select schemamap.define_concept('foreign_key', $$
  select exists (
    select 1
    from jsonb_array_elements(smo.constraints) as c
    where (c->>'type') = 'f'
  );
$$);

select schemamap.define_concept('unique_key', $$
  select exists (
    select 1
    from jsonb_array_elements(smo.constraints) as c
    where (c->>'type') = 'u'
  )
  or
  exists (
    select 1
    from jsonb_array_elements(smo.indexes) as i
    where (i->>'type') = 'u'
  );
$$);

select schemamap.define_concept('check_constrained', $$
  select exists (
    select 1
    from jsonb_array_elements(smo.constraints) as c
    where (c->>'type') = 'c'
  );
$$);

select schemamap.define_concept('exclusion_constrained', $$
  select exists (
    select 1
    from jsonb_array_elements(smo.constraints) as c
    where (c->>'type') = 'x'
  );
$$);

select schemamap.define_concept('indexed', $$
  select exists (
    select 1
    from jsonb_array_elements(smo.constraints) as i
    where (i->>'type') in ('p',' u', 'x')
  ) or
  exists (
    select 1
    from jsonb_array_elements(smo.indexes) as i
    where (i->>'type') in ('i',' u', 'x')
  );
$$);

select schemamap.define_concept('generated', $$
  select exists (
    select 1
    from jsonb_array_elements(smo.constraints) as c
    where (c->>'type') = 'g'
  );
$$);

select schemamap.define_concept('natural_key', $$
  select exists (
    select 1
    from jsonb_array_elements(smo.constraints) as c
    where
      (c->>'type') = 'p' and
      (jsonb_typeof(c->'sequence_name') = 'null')
  ) and smo.default_value is null;
$$);

select schemamap.define_concept('surrogate_key', $$
  select schemamap.is_primary_key(smo) and not schemamap.is_natural_key(smo);
$$);

select schemamap.define_concept('self_reference', $$
  select exists (
    select 1
    from jsonb_array_elements(smo.constraints) as c
    where (c->>'type') = 'f' and
          (c->>'definition') ilike ('% REFERENCES ' || smo.table_name || '(%')
  );
$$);

select schemamap.define_concept('external_reference', $$
  select
    not schemamap.is_foreign_key(smo) and
    (smo.column_name ilike '%_id' or
     smo.column_name ilike '%url%' or
     smo.column_name ilike '%uri%' or
     smo.column_name ilike '%_ref%' or
     smo.column_name ilike '%_code%' or
     smo.column_name ilike '%uuid%' or
     smo.column_name ilike '%guid%' or
     smo.column_name ilike '%external_%'
    );
$$);

create or replace view schemamap.status as
select
  count(distinct schema_name) as schema_count,
  count(distinct (schema_name, table_name)) as table_count,
  count(*) as column_count,
  count(distinct (schema_name, table_name)) filter (where is_schema_migration_table) as schema_migration_table_count,
  count(*) filter (where is_pii) as pii_count,
  count(*) filter (where is_metadata) as metadata_count,
  count(*) filter (where is_primary_key) as primary_key_count,
  count(*) filter (where is_foreign_key) as foreign_key_count,
  count(*) filter (where is_unique_key) as unique_key_count,
  count(*) filter (where is_check_constrained) as check_constrained_count,
  count(*) filter (where is_exclusion_constrained) as exclusion_constrained_count,
  count(*) filter (where is_indexed) as indexed_count,
  count(*) filter (where is_generated) as generated_count,
  count(*) filter (where is_natural_key) as natural_key_count,
  count(*) filter (where is_surrogate_key) as surrogate_key_count,
  count(*) filter (where is_self_reference) as self_reference_count,
  count(*) filter (where is_external_reference) as external_reference_count,
  (select jsonb_agg(tenants order by tenant_id) from schemamap.list_tenants() as tenants) as tenants,
  (select jsonb_agg(mdes order by mde_name) from schemamap.list_mdes() as mdes) as master_data_entities
from schemamap.smo;
