-- TODO: replace `PUBLIC` with your application DB role(s)
grant usage on schema schemamap to PUBLIC;

-- These changes allow your application roles & migrations to use the stored procedures, like:
-- select * from schemamap.verify_installation();
grant execute on all functions in schema schemamap to PUBLIC;
alter default privileges in schema schemamap grant execute ON functions TO PUBLIC;

-- These changes allow your application roles & migrations to check the status of data_migrations
-- and their related tables: \dt schemamap.dm_*
-- select * from schemamap.data_migrations;
grant select on all tables in schema schemamap to PUBLIC;
alter default privileges in schema schemamap grant select on tables to PUBLIC;

-- this change allows schemamap to always execute functions, even if created by other roles
alter default privileges in schema schemamap grant execute ON functions TO schemamap;
