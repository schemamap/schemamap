use std::{
    fs::File,
    io::{self, BufRead},
};

use tokio_postgres::Config;

fn parse_pgpass_line(line: &str) -> Option<Config> {
    let parts: Vec<&str> = line.split(':').collect();
    if parts.len() == 5 {
        let mut config = Config::new();
        config
            .host(parts[0])
            .port(parts[1].parse().ok()?)
            .dbname(parts[2])
            .user(parts[3])
            .password(parts[4]);
        Some(config)
    } else {
        None
    }
}

pub(crate) fn get_pg_config() -> anyhow::Result<Config> {
    if let Some(home_dir) = dirs::home_dir() {
        let pgpass_path = home_dir.join(".pgpass");
        if pgpass_path.exists() {
            let file = File::open(pgpass_path)?;
            for line in io::BufReader::new(file).lines() {
                let line = line?;
                if let Some(config) = parse_pgpass_line(&line) {
                    return Ok(config);
                }
            }
        }
    }
    Err(anyhow::anyhow!("No .pgpass file found"))
}

#[cfg(test)]
mod tests {

    use tokio_postgres::config::Host;

    use super::*;

    #[test]
    fn test_parse_pgpass_line() {
        let line = "localhost:5432:database:user:password";
        let config = parse_pgpass_line(line).unwrap();
        assert_eq!(config.get_hosts(), vec![Host::Tcp("localhost".to_string())]);
        assert_eq!(config.get_ports(), vec![5432]);
        assert_eq!(config.get_user(), Some("user"));
        assert_eq!(config.get_dbname(), Some("database"));
        assert_eq!(config.get_password(), Some(&b"password"[..]));
    }
}
