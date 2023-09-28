create table schemamap.i18n_stored (
    value jsonb not null
);

insert into schemamap.i18n_stored values ('{}'::jsonb);

revoke insert on schemamap.i18n_stored from public;

create or replace function schemamap.i18n()
returns jsonb as $$
  select value from schemamap.i18n_stored
$$ language sql stable;
