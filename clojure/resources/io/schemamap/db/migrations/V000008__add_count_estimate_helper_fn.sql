create or replace function schemamap.count_estimate(query text)
returns bigint as $$
declare
  plan jsonb;
begin
    execute 'explain (format json) ' || query into plan;
    return (plan->0->'Plan'->'Plan Rows')::bigint;
end $$ language plpgsql volatile;
