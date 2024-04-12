-- fix typo
alter function master_date_entity_candidates rename to master_data_entity_candidates;

-- helper 0-arity to return updatable UDFs
create or replace function schemamap.update_function_definition()
returns table(function_name text, "returns" text, "language" text) as $$
  select
    pp.proname as function_name,
    pg_catalog.pg_get_function_result(pp.oid) as "returns",
    pl.lanname as "language"
  from pg_proc pp
  join pg_namespace pn on pn.oid = pp.pronamespace
  join pg_language pl on pl.oid = pp.prolang
  where
    pn.nspname = 'schemamap' and
    pl.lanname = 'sql' and
    pp.provolatile != 'v' and
    nullif(pg_catalog.pg_get_function_arguments(pp.oid), '') is null and

    pp.proname not in
      (select forward_fn_name from schemamap.bidi_mapping_fns
      union all
      select backward_fn_name from schemamap.bidi_mapping_fns
      union all
      values ('verify_installation'), ('list_mdes'), ('master_data_entity_candidates'), ('update_function_definition'));
$$ language sql stable;

-- helper 1-arity to get the current definition value
create or replace function schemamap.update_function_definition(function_name text)
returns text as $$
  select schemamap.get_function_definition($1);
$$ language sql stable;
