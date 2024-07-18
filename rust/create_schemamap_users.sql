-- check if the current user has superuser/role creation privileges
do $$
begin
  if (select rolsuper or rolcreaterole as valid_role from pg_roles where rolname = current_user) is not true then
    raise exception 'This script must be run by a superuser (usually "postgres" or $(whoami)).';
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
