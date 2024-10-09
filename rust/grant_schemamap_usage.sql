-- transfer ownership of schemamap schema from creating role to schemamap user
grant schemamap to CURRENT_USER;
alter schema schemamap owner to schemamap;

grant all privileges on all tables in schema schemamap to schemamap;
grant all privileges on all sequences in schema schemamap to schemamap;
grant all privileges on all functions in schema schemamap to schemamap;
grant all privileges on all procedures in schema schemamap to schemamap;

-- transfer ownership of individual objects within 'schemamap' schema
do $$
declare
    rec record;
begin
    for rec in select tablename from pg_catalog.pg_tables where schemaname = 'schemamap'
    loop
        execute format('alter table schemamap.%I owner to schemamap', rec.tablename);
    end loop;

    for rec in select sequencename from pg_catalog.pg_sequences where schemaname = 'schemamap'
    loop
        execute format('alter sequence schemamap.%I owner to schemamap', rec.sequencename);
    end loop;

    for rec in select viewname from pg_catalog.pg_views where schemaname = 'schemamap'
    loop
        execute format('alter view schemamap.%I owner to schemamap', rec.viewname);
    end loop;

    for rec in select matviewname from pg_catalog.pg_matviews where schemaname = 'schemamap'
    loop
        execute format('alter materialized view schemamap.%I owner to schemamap', rec.matviewname);
    end loop;

    for rec in
        select 'alter function '||
            quote_ident(nsp.nspname) ||
            '.' ||
            quote_ident(p.proname) ||
            '(' ||
            pg_get_function_identity_arguments(p.oid) ||
            ') owner to schemamap;' as func_stmt
        from pg_proc p
        join pg_namespace nsp on p.pronamespace = nsp.oid
        where nsp.nspname = 'schemamap'
    loop
        execute rec.func_stmt;
    end loop;
end $$;

-- TODO: replace `PUBLIC` with your application DB role(s)
grant usage, create on schema schemamap to PUBLIC;

-- These changes allow your application roles & migrations to use the stored procedures, like:
-- select * from schemamap.verify_installation();
grant execute on all functions in schema schemamap to PUBLIC;
alter default privileges in schema schemamap grant execute ON functions TO PUBLIC;

-- These changes allow your application roles & migrations to check the status of data_migrations
-- and their related tables: \dt schemamap.dm_*
-- select * from schemamap.data_migrations;
grant select on all tables in schema schemamap to PUBLIC;
alter default privileges in schema schemamap grant select on tables to PUBLIC;

-- allow all operations on data migration table, so import/dispose functions can UPDATE/DELETE records
grant all on schemamap.data_migrations to PUBLIC;

-- this change allows schemamap to always execute functions, even if created by other roles
alter default privileges in schema schemamap grant execute ON functions TO schemamap;

revoke schemamap from CURRENT_USER;
