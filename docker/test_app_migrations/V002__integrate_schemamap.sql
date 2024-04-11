grant usage on schema public to schemamap;

select schemamap.update_function_definition('ignored_schemas', $$
  values ('pg_catalog'), ('information_schema'), ('schemamap'), ('some_schema_that_doesnt_exist')
$$);

grant select on organizations to schemamap;

select schemamap.update_function_definition('list_tenants', $$
  select
    id as tenant_id,
    left(replace(lower(name), ' ', '_'), 10) as tenant_short_name,
    name as tenant_display_name,
    'en_US' as tenant_locale,
    jsonb_build_object('website', website, 'createdAt', created_at) as tenant_data
  from organizations;
$$);

grant select on projects to schemamap;

select schemamap.define_master_data_entity('projects', $$
  select * from projects;
$$);

select schemamap.update_schema_metadata_overview();

select * from schemamap.schema_metadata_overview;
