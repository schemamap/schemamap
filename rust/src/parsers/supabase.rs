use serde::Deserialize;
use std::fs::File;
use std::io::Read;
use std::path::Path;
use tokio_postgres::Config;

#[derive(Debug, Deserialize)]
struct SupabaseConfig {
    #[serde(rename = "db")]
    database: DatabaseConfig,
}

#[derive(Debug, Deserialize)]
struct DatabaseConfig {
    #[serde(rename = "user")]
    username: String,
    password: String,
    host: String,
    port: u16,
    dbname: String,
}

fn parse_supabase_config(file_path: &Path) -> anyhow::Result<SupabaseConfig> {
    let mut file = File::open(file_path)?;
    let mut contents = String::new();
    file.read_to_string(&mut contents)?;
    let config: SupabaseConfig = toml::from_str(&contents)?;
    Ok(config)
}

fn get_pg_config_from_supabase(config: &SupabaseConfig) -> Config {
    let mut pg_config = Config::new();
    pg_config
        .host(&config.database.host)
        .port(config.database.port)
        .user(&config.database.username)
        .password(&config.database.password)
        .dbname(&config.database.dbname);
    pg_config
}

pub(crate) fn get_pg_config() -> anyhow::Result<Config> {
    let cwd = std::env::current_dir()?;
    let file_path = cwd.join("supabase/config.toml");

    let supabase_config = parse_supabase_config(&file_path)?;

    Ok(get_pg_config_from_supabase(&supabase_config))
}
