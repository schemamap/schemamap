-- check if the current user is schemamap
do $$
begin
  if (select true from pg_roles where rolname = 'schemamap') is not true then
    raise exception 'Please run this migration using the schemamap user so it automatically has correct ownership';
  end if;
end $$;
