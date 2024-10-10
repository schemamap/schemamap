use tokio_postgres::{config::Host, Config};

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

    log::info!("Using Postgres connection params:");
    log::info!(
        "host={} port={} user={} dbname={}",
        config
            .get_hosts()
            .get(0)
            .map(|h| match h {
                Host::Tcp(host) => host.clone(),
                #[cfg(unix)]
                Host::Unix(path) => path.to_string_lossy().into_owned(),
            })
            .unwrap_or_default(),
        config
            .get_ports()
            .get(0)
            .map(|p| p.to_string())
            .unwrap_or_default(),
        config.get_user().unwrap_or_default(),
        config.get_dbname().unwrap_or_default()
    );

    Ok(config)
}
