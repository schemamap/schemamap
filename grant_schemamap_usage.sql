-- This changes allow your application migrations to use the stored procedures, like:
-- select * from schemamap.verify_installation();

-- TODO: replace `PUBLIC` with your application DB role(s)
grant usage on schema schemamap to PUBLIC;
grant execute on all functions in schema schemamap to PUBLIC;
grant select on all tables in schema schemamap to PUBLIC;
