-- check if the current user is schemamap
do $$
begin
  if (select current_role  = 'schemamap') is not true then
    raise exception 'Please run this schema migration using the schemamap user so it automatically has correct ownership';
  end if;
end $$;
