use serde::Deserialize;
use std::fs::File;
use std::io::Read;
use std::path::Path;
use tokio_postgres::Config;

#[derive(Debug, Deserialize)]
struct DockerCompose {
    services: std::collections::HashMap<String, Service>,
}

#[derive(Debug, Deserialize)]
struct Service {
    image: Option<String>,
    environment: Option<std::collections::HashMap<String, String>>,
}

fn parse_docker_compose(file_path: &Path) -> anyhow::Result<DockerCompose> {
    let mut file = File::open(file_path)?;
    let mut contents = String::new();
    file.read_to_string(&mut contents)?;
    let docker_compose: DockerCompose = serde_yaml::from_str(&contents)?;
    Ok(docker_compose)
}

fn get_pg_config_from_docker_compose(docker_compose: &DockerCompose) -> Option<Config> {
    for (_name, service) in &docker_compose.services {
        if let Some(image) = &service.image {
            if image.contains("postgres") {
                if let Some(env) = &service.environment {
                    let host = env.get("PGHOST").map(|s| s.as_str()).unwrap_or("localhost");
                    let port = env
                        .get("PGPORT")
                        .and_then(|s| s.parse().ok())
                        .unwrap_or(5432);
                    let user = env.get("POSTGRES_USER")?;
                    let password = env.get("POSTGRES_PASSWORD")?;
                    let dbname = env.get("POSTGRES_DB")?;

                    let mut config = Config::new();
                    config
                        .host(host)
                        .port(port)
                        .user(user)
                        .password(password)
                        .dbname(dbname);
                    return Some(config);
                }
            }
        }
    }
    None
}

pub(crate) fn get_pg_config() -> anyhow::Result<Config> {
    let cwd = std::env::current_dir().unwrap();
    let file_path = cwd.join("docker-compose.yml");

    // Parse the docker-compose.yml file
    let docker_compose = parse_docker_compose(&file_path)?;

    match get_pg_config_from_docker_compose(&docker_compose) {
        Some(config) => Ok(config),
        None => Err(anyhow::Error::msg(
            "Docker-compose Postgres config not found",
        )),
    }
}
