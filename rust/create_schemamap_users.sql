-- check if the current user has superuser/role creation privileges
do $$
begin
  if (select rolsuper or rolcreaterole as valid_role from pg_roles where rolname = current_user) is not true then
    raise exception 'This script must be run by a user with CREATE ROLE privileges (usually "postgres" or $(whoami)).';
  end if;
end $$;

-- Create the roles
-- TODO: change the passwords!
create user schemamap with connection limit 5 encrypted password 'schemamap';

-- Extra roles, if you want to be extra safe/more granular with permissions
-- otherwise, feel free to remove.
create user schemamap_schema_read with connection limit 5 password 'schemamap_schema_read';
create user schemamap_readonly with connection limit 5 password 'schemamap_readonly';
create user schemamap_readwrite with connection limit 5 password 'schemamap_readwrite';

-- create role capability hierarchy: least to most permissive
grant schemamap_schema_read to schemamap_readonly;
grant schemamap_readonly to schemamap_readwrite;
grant schemamap_readwrite to schemamap;

-- TODO: afterwards, grant connectivity to the database
-- grant connect, create on database $POSTGRES_DB to schemamap;

-- for better DX, grant usage to all schemas so the initial migration sees full DB graph
do $$
declare
    rec record;
begin
    for rec in
        select schema_name
        from information_schema.schemata
        where schema_name not in ('pg_catalog', 'information_schema', 'pg_toast')
    loop
        execute format('grant usage on schema %I to schemamap_schema_read', rec.schema_name);
    end loop;
end $$;

-- allow usage on all schemas created by the current (administrator) role
alter default privileges grant usage on schemas to schemamap_schema_read;
