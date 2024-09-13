use std::env;

use tokio_postgres::Config;

pub(crate) fn config_from_env() -> Result<Config, anyhow::Error> {
    // Prefer DATABASE_URL over PG* env vars

    let database_config = match env::var("DATABASE_URL") {
        Ok(url) => {
            if url.is_empty() {
                log::debug!("DATABASE_URL is empty");
                Err(())
            } else {
                log::debug!("Parsing DATABASE_URL");
                Ok(url.parse::<Config>()?)
            }
        }
        Err(_) => Err(()),
    };

    if database_config.is_ok() {
        return Ok(database_config.unwrap());
    }

    let host = env::var("PGHOST").ok();
    let port = env::var("PGPORT").ok().and_then(|p| p.parse().ok());
    let user = env::var("PGUSER").ok();
    let password = env::var("PGPASSWORD").ok();
    let dbname = env::var("PGDATABASE").ok();

    if host.is_some() && port.is_some() && user.is_some() && password.is_some() && dbname.is_some()
    {
        let mut config = Config::new();
        config
            .host(host.as_deref().unwrap())
            .port(port.unwrap())
            .user(user.as_deref().unwrap())
            .password(password.as_deref().unwrap())
            .dbname(dbname.as_deref().unwrap());
        Ok(config)
    } else {
        Err(anyhow::anyhow!("Missing required environment variables"))
    }
}

#[cfg(test)]
mod tests {
    use std::env;

    use tokio_postgres::config::Host;

    use super::*;

    #[test]
    fn test_config_from_env() {
        // Setting this empty so it surronding cargo test env vars don't interfere with the below tests
        env::set_var("DATABASE_URL", "");

        env::set_var("PGHOST", "localhost");
        env::set_var("PGPORT", "5432");
        env::set_var("PGUSER", "user");
        env::set_var("PGPASSWORD", "password");
        env::set_var("PGDATABASE", "database");

        let config = config_from_env().unwrap();
        assert_eq!(config.get_hosts(), vec![Host::Tcp("localhost".to_string())]);
        assert_eq!(config.get_ports(), vec![5432]);
        assert_eq!(config.get_user(), Some("user"));
        assert_eq!(config.get_dbname(), Some("database"));
        assert_eq!(config.get_password(), Some(&b"password"[..]));

        env::remove_var("PGHOST");
        env::remove_var("PGPORT");
        env::remove_var("PGUSER");
        env::remove_var("PGPASSWORD");
        env::remove_var("PGDATABASE");
    }
}
