use std::env;

use tokio_postgres::Config;

pub(crate) fn get_pg_config(
    dbname: Option<String>,
    username: Option<String>,
    port: Option<u16>,
) -> Config {
    // Last resort, use default for default Postgres Docker image:
    // $ docker run --name some-postgres -e POSTGRES_PASSWORD=mysecretpassword -d postgres
    let dbname =
        dbname.unwrap_or_else(|| env::var("POSTGRES_DB").unwrap_or("postgres".to_string()));
    let username =
        username.unwrap_or_else(|| env::var("POSTGRES_USER").unwrap_or("postgres".to_string()));
    let port = port.unwrap_or(5432);
    let password = env::var("POSTGRES_PASSWORD")
        .unwrap_or_else(|_| env::var("PGPASSWORD").unwrap_or("postgres".to_string()));

    let pgdata = env::var("PGDATA").ok();
    let host = pgdata.clone().unwrap_or_else(|| "localhost".to_string());

    let config_str = if pgdata.is_some() {
        log::info!("Using PGDATA environment variable to connect to Postgres");
        format!(
            "host={} user={} dbname={} password={}",
            host, username, dbname, password
        )
    } else {
        log::info!("Using TCP-based image to connect to Postgres");
        format!(
            "host={} user={} dbname={} password={} port={}",
            host, username, dbname, password, port,
        )
    };

    config_str.parse::<Config>().unwrap()
}
