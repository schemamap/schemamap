use tokio_postgres::Config;

mod default;
mod docker_compose;
mod env;
mod hasura;
mod pgpass;
mod pgsync;
mod supabase;

pub(crate) fn parse_pgconfig(
    dbname: Option<String>,
    username: Option<String>,
    conn: Option<String>,
    port: Option<u16>,
) -> anyhow::Result<Config> {
    log::debug!("Parsing PG connection configuration");
    Ok(conn.map_or_else(
        || {
            // TODO: review priority
            return env::config_from_env()
                .or_else(|_| docker_compose::get_pg_config())
                .or_else(|_| supabase::get_pg_config())
                .or_else(|_| pgsync::get_pg_config())
                .or_else(|_| hasura::get_pg_config())
                .or_else(|_| pgpass::get_pg_config())
                // TODO: pass in dbname/username from CLI
                .or_else(|_| Ok(default::get_pg_config(dbname, username, port)));
        },
        |conn_str| conn_str.parse::<Config>(),
    )?)
}
