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

    let mut config = if let Some(conn_str) = conn {
        conn_str.parse::<Config>()?
    } else {
        // TODO: review priority
        env::config_from_env()
            .or_else(|_| docker_compose::get_pg_config())
            .or_else(|_| supabase::get_pg_config())
            .or_else(|_| pgsync::get_pg_config())
            .or_else(|_| hasura::get_pg_config())
            .or_else(|_| pgpass::get_pg_config())
            .unwrap_or_else(|_| default::get_pg_config(dbname.clone(), username.clone(), port))
    };

    // Explicit args take precedence over inferred config values
    if let Some(dbname) = dbname {
        config.dbname(&dbname);
    }
    if let Some(username) = username {
        config.user(&username);
    }
    if let Some(port) = port {
        config.port(port);
    }

    Ok(config)
}
