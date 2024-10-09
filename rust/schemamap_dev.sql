-- Development time DB snapshot/restore helpers from https://schemamap.dev
-- Installation:
-- CREATE DATABASE schemamap_dev;
-- \c schemamap_dev
-- begin; \i schemamap_dev.sql
-- commit;
--
-- Usage:
-- select create_snapshot(template_db_name := 'postgres', new_db_name := 'postgres_copy');
-- select restore_snapshot(template_db_name := 'postgres_copy', new_db_name := 'postgres');

do $$
begin
  if (select rolsuper from pg_roles where rolname = current_user) is not true then
    raise exception 'This development-time script must be run by a user with superuser privileges (usually "postgres" or $(whoami)).';
  end if;

  -- safe-guard against people accidentally running against some random live DB
  if (select current_database()) != 'schemamap_dev' then
    raise exception 'This dangerous dev-time only script can only be run on database called "schemamap_dev"';
  end if;
end $$;

-- dblink is needed to hack around transaction consistency guarantees within functions
-- for CREATE DATABASE/DROP DATABASE
-- NOTE: this means each database-level operation opens a short-lived local backend process
create extension if not exists dblink;

create table if not exists snapshots (
  db_name text primary key,
  template_db_name text not null,
  git_branch text,
  git_rev text,
  created_at timestamptz not null default now()
);

create or replace function disallow_and_kill_connections(db_name snapshots.db_name%type)
returns void as $$
begin
  -- NOTE: needed to avoid race conditions with connect()-happy clients
  -- MUST be reenabled with `allow_connections()`
  execute format('alter database %I with allow_connections false', $1);

  perform pg_cancel_backend(pg_stat_activity.pid)
    from pg_stat_activity
    where datname = $1 and
          pid != pg_backend_pid();

  perform pg_terminate_backend(pg_stat_activity.pid)
    from pg_stat_activity
    where datname = $1 and
          pid != pg_backend_pid();
end; $$ language plpgsql volatile;

create or replace function allow_connections(db_name snapshots.db_name%type)
returns void as $$
begin
  execute format('alter database %I with allow_connections true', $1);
end; $$ language plpgsql volatile;


create or replace function pg_major_version()
returns smallint as $$
  select split_part(current_setting('server_version'), '.', 1)::smallint
$$ language sql immutable;

-- high-level API
create or replace function drop_database(db_name snapshots.db_name%type)
returns void as $$
begin
  if (select exists (select 1 from pg_catalog.pg_database where datname = $1)) = true then
    -- NOTE: because of lock contention using dblink_exec the DROP DATABASE hangs forever on a pg_database tuple lock
    -- The deletion of the files happens quickly, and the database is left corrupted
    -- HACK: fail using statement_timeout and clean up the final step of the DROP DATABASE manually;
    if (select pg_major_version()) >= 13 then
      perform dblink_exec(
        format('dbname=schemamap_dev user=%I options=''-c statement_timeout=500 -c lock_timeout=100''', current_user),
        format('drop database %I with (force)', db_name),
        false);
    else
      perform pg_terminate_backend(pg_stat_activity.pid)
        from pg_stat_activity
        where datname = $1 and
              pid != pg_backend_pid();

      perform dblink_exec(
        format('dbname=schemamap_dev user=%I options=''-c statement_timeout=500 -c lock_timeout=100''', current_user),
        format('drop database if exists %I', db_name),
        false);
    end if;

    -- HACK: find a better way to do this, see above
    delete from pg_catalog.pg_database where datname = $1;
  end if;
end; $$ language plpgsql volatile;

create or replace function create_snapshot(template_db_name snapshots.db_name%type, new_db_name snapshots.db_name%type)
returns void as $$
declare
  start_time timestamp;
  end_time timestamp;
begin
  start_time := clock_timestamp();

  perform drop_database(new_db_name); -- in case it already exists

  perform disallow_and_kill_connections(template_db_name);
  perform dblink_exec(
    format('dbname=schemamap_dev user=%I', current_user),
    format('create database %I template %I', new_db_name, template_db_name));
  perform allow_connections(template_db_name);

  end_time := clock_timestamp();

  insert into snapshots (db_name, template_db_name) values ($2, $1) on conflict (db_name) do update set created_at = now();

  raise notice '% DB created from %! Elapsed time: % milliseconds', new_db_name, template_db_name, extract(millisecond from end_time - start_time);
end; $$ language plpgsql volatile;

create or replace function restore_snapshot(template_db_name snapshots.db_name%type, new_db_name snapshots.db_name%type)
returns void as $$
declare
  start_time timestamp;
  end_time timestamp;
begin
  start_time := clock_timestamp();

  perform dblink_exec(
    format('dbname=schemamap_dev user=%I', current_user),
    format('create database %I template %I', new_db_name, template_db_name));

  end_time := clock_timestamp();

  raise notice '% DB restored from %! Elapsed time: % milliseconds', new_db_name, template_db_name, extract(millisecond from end_time - start_time);
end; $$ language plpgsql volatile;

create or replace function drop_snapshot(db_name snapshots.db_name%type)
returns void as $$
begin
  raise notice 'Dropping DB: %', db_name;

  perform drop_database($1);

  delete from snapshots where snapshots.db_name = $1;

  raise notice 'Dropped DB: %', db_name;
end; $$ language plpgsql volatile;

create or replace function gc_snapshots()
returns void as $$
begin
  perform drop_snapshot(snapshots.db_name)
  from snapshots
  where db_name not in (
    select datname from pg_database
  );
end; $$ language plpgsql volatile;
