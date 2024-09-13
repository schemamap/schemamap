use docker_compose_types::{Compose, Ports};
use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
use std::path::Path;
use tokio_postgres::Config;

fn parse_docker_compose(file_path: &Path) -> anyhow::Result<Compose> {
    let mut file = File::open(file_path)?;
    let mut contents = String::new();
    file.read_to_string(&mut contents)?;
    let compose_file: Compose = serde_yaml::from_str(&contents)?;
    Ok(compose_file)
}

fn parse_port(ports: &Ports, env_map: &HashMap<String, String>) -> u16 {
    match ports {
        docker_compose_types::Ports::Short(v) => {
            log::debug!("Parsing docker-compose ports: {:?}", v);
            v.iter()
                .find_map(|p| {
                    let split_port: Vec<&str> = p.splitn(3, ':').collect();
                    if split_port.len() == 2 {
                        Some(split_port[0])
                    } else if split_port.len() == 3 {
                        Some(split_port[1])
                    } else {
                        None
                    }
                    .map(|p| p.parse::<u16>().ok())
                })
                .unwrap_or_default()
        }
        docker_compose_types::Ports::Long(ports_long) => ports_long
            .iter()
            .find_map(|p| {
                p.published.as_ref().map(|p| match p {
                    docker_compose_types::PublishedPort::Single(sp) => Some(sp.clone()),
                    // NOTE: this does not make sense for the official Postgres image
                    docker_compose_types::PublishedPort::Range(_) => None,
                })
            })
            .unwrap_or_default(),
    }
    .unwrap_or_else(|| {
        env_map
            .get("PGPORT")
            .unwrap_or(&"5432".to_string())
            .parse::<u16>()
            .unwrap_or(5432)
    })
}

fn get_pg_config_from_docker_compose(compose: &Compose) -> Option<Config> {
    for (service_name, opt_service) in &compose.services.0 {
        if let Some(service) = opt_service {
            match &service.image {
                Some(image) => {
                    if image.contains("postgres") {
                        log::info!(
                            "Found Postgres service in Docker-compose YAML file: {}",
                            service_name
                        );

                        let env = &service.environment;

                        let env_map = match env {
                            docker_compose_types::Environment::List(env_list) => env_list
                                .iter()
                                .map(|env| env.split_once('='))
                                .filter_map(|opt| opt.map(|(k, v)| (k.to_string(), v.to_string())))
                                .collect::<HashMap<String, String>>(),
                            docker_compose_types::Environment::KvPair(kv) => kv
                                .iter()
                                .filter_map(|(k, v)| {
                                    if let Some(v) = v {
                                        Some((k.to_string(), v.to_string()))
                                    } else {
                                        None
                                    }
                                })
                                .collect::<HashMap<String, String>>(),
                        };

                        let mut config = Config::new();

                        config.host(
                            env_map
                                .get("POSTGRES_HOST")
                                .unwrap_or(&"localhost".to_string()),
                        );

                        config.port(parse_port(&service.ports, &env_map));

                        config.user(
                            env_map
                                .get("POSTGRES_USER")
                                .unwrap_or(&"postgres".to_string()),
                        );

                        config.password(
                            env_map
                                .get("POSTGRES_PASSWORD")
                                .unwrap_or(&"postgres".to_string()),
                        );

                        config.dbname(
                            env_map
                                .get("POSTGRES_DB")
                                .unwrap_or(&"postgres".to_string()),
                        );

                        return Some(config);
                    } else {
                        continue;
                    }
                }
                None => {
                    continue;
                }
            }
        }
    }
    None
}

pub(crate) fn get_pg_config() -> anyhow::Result<Config> {
    let cwd = std::env::current_dir().unwrap();
    // As per: https://docs.docker.com/compose/compose-application-model/#the-compose-file
    let yaml_file_preferences = vec![
        "compose.yaml",
        "compose.yml",
        "docker-compose.yml",
        "docker-compose.yaml",
    ];

    for yaml_file_preference in yaml_file_preferences {
        let file_path = cwd.join(yaml_file_preference);

        if !file_path.exists() {
            continue;
        }

        log::debug!(
            "Checking for Docker-compose Postgres config in {}",
            file_path.display()
        );

        let docker_compose = match parse_docker_compose(&file_path) {
            Ok(docker_compose) => docker_compose,
            Err(e) => {
                log::warn!(
                    "Failed to parse Docker-compose YAML file {}: {}",
                    file_path.display(),
                    e
                );
                continue;
            }
        };

        match get_pg_config_from_docker_compose(&docker_compose) {
            Some(config) => {
                log::info!(
                    "Using Docker-compose Postgres config from {}",
                    file_path.display()
                );
                return Ok(config);
            }
            None => {
                log::debug!(
                    "No Docker-compose Postgres config found in {}",
                    file_path.display()
                );
                continue;
            }
        };
    }

    return Err(anyhow::Error::msg(
        "No valid Docker-compose Postgres config found",
    ));
}
