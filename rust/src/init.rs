use crate::common::{Cli, SCHEMAMAP_DEV_DB};
use anyhow::Result;
use clap::Args;
use dialoguer::theme::ColorfulTheme;
use tokio_postgres::{Client, Config, NoTls};

use crate::parsers;

const CREATE_SCHEMAMAP_USERS_SQL: &str = include_str!("../create_schemamap_users.sql");
const CREATE_SCHEMAMAP_SCHEMA_SQL: &str = include_str!("../create_schemamap_schema.sql");
const GRANT_SCHEMAMAP_USAGE_SQL: &str = include_str!("../grant_schemamap_usage.sql");

const SCHEMAMAP_DEV_SQL: &str = include_str!("../schemamap_dev.sql");

// Closely simulating psql cli arguments
#[derive(Args)]
pub struct InitArgs {
    #[arg(
        long,
        help = "Ask for inputs if not provided",
        default_missing_value = "true",
        default_value = "true",
        num_args =0..=1,
        action = clap::ArgAction::Set,
    )]
    input: Option<bool>,

    // Until https://github.com/clap-rs/clap/issues/5577 is addressed
    // have to do this for falsey-by-default flags
    #[arg(long,
        help = "Install development-time extensions, like DB snapshot/restore.",
        default_missing_value = "true",
        num_args =0..=1,
        action = clap::ArgAction::Set
    )]
    dev: Option<bool>,

    // Until https://github.com/clap-rs/clap/issues/5577 is addressed
    // have to do this for falsey-by-default flags
    #[arg(
        long,
        help = "Print SQL statements without executing them",
        default_missing_value = "true",
        default_value = "false",
        num_args =0..=1,
        action = clap::ArgAction::Set,
      )]
    pub(crate) dry_run: Option<bool>,
}

pub(crate) fn initialize_pgconfig(cli: &Cli, interactive: bool) -> tokio_postgres::Config {
    let pgconfig =
            parsers::parse_pgconfig(cli.dbname.clone(), cli.username.clone(), cli.conn.clone(), cli.port)
            .unwrap_or_else(|_e| {
                if interactive {
                    prompt_for_pg_connstring()
                        .parse::<tokio_postgres::Config>()
                        .unwrap()
                } else {
                    log::error!("No PG connection string provided, please provide a connection string via --conn or DATABASE_URL environment variable");
                    std::process::exit(1);
                }
            });

    log::debug!("Using connection string: {:?}", pgconfig);

    return pgconfig;
}

pub async fn set_search_path(client: &Option<Client>) -> Result<()> {
    let set_search_path_sql = "SET search_path TO schemamap;";
    if let Some(c) = client {
        c.simple_query(&set_search_path_sql).await?;
    } else {
        println!("{}", set_search_path_sql);
    }
    Ok(())
}

pub async fn create_schemamap_users(dbname: &String, client: &Option<Client>) -> Result<()> {
    if let Some(c) = client {
        log::info!("Creating Schemamap.io users in {}", dbname);

        let _ = c
            .batch_execute(CREATE_SCHEMAMAP_USERS_SQL)
            .await
            .inspect_err(|e| {
                if e.to_string().contains("already exists") {
                    log::info!("Skipping schemamap users creation, they already exist.");
                } else {
                    log::warn!("Failed to create schemamap users: {}", e);
                }
            });
    } else {
        println!("{}", CREATE_SCHEMAMAP_USERS_SQL);
    }
    Ok(())
}

async fn grant_create_connect(dbname: &str, client: &Option<Client>) -> Result<()> {
    let grant_create_connect_sql =
        format!("GRANT CREATE, CONNECT ON DATABASE {} TO schemamap;", dbname);
    if let Some(c) = client {
        c.simple_query(&grant_create_connect_sql).await?;
    } else {
        println!("{}", grant_create_connect_sql);
    }
    Ok(())
}

pub async fn create_schemamap_schema(client: &Option<Client>) -> Result<()> {
    if let Some(c) = client {
        let _ = c
            .batch_execute(CREATE_SCHEMAMAP_SCHEMA_SQL)
            .await
            .inspect_err(|e| log::warn!("Failed to create schemamap schema: {}", e));
    } else {
        println!("{}", CREATE_SCHEMAMAP_SCHEMA_SQL);
    }
    Ok(())
}

fn remove_after_dot(s: &str) -> &str {
    match s.find('.') {
        Some(index) => &s[..index],
        None => s,
    }
}

fn normalize_username<'a>(pgconfig: &'a Config, username: &'a str) -> &'a str {
    // NOTE: Supabase uses a $user.$dbid to dispatch to the the correct DB
    if let Some(first_host) = pgconfig.get_hosts().get(0) {
        if let tokio_postgres::config::Host::Tcp(host_str) = first_host {
            if host_str.contains("supabase.com") {
                return remove_after_dot(username);
            }
        }
    }
    username
}

pub async fn grant_schemamap_usage(pgconfig: &Config, client: &Option<Client>) -> Result<()> {
    // NOTE: without this Supabase via Supavisor/PGBouncer disconnects on CURRENT_USER
    let current_user = normalize_username(pgconfig, pgconfig.get_user().unwrap_or("postgres"));

    let current_user_replaced_sql = GRANT_SCHEMAMAP_USAGE_SQL
        .replace(" CURRENT_USER;", format!(" \"{}\";", current_user).as_str());

    if let Some(c) = client {
        let _ = c
            .batch_execute(&current_user_replaced_sql)
            .await
            .inspect_err(|e| log::warn!("Failed to grant schemamap usage: {}", e));
    } else {
        println!("{}", current_user_replaced_sql);
    }
    Ok(())
}

pub async fn install_dev_extensions(pgconfig: &Config, client: &Option<Client>) -> Result<()> {
    // Have to submit separately otherwise the commands run in a transaction context
    // which is not allowed for CREATE DATABASE.

    log::info!("Creating \"{}\" DB", SCHEMAMAP_DEV_DB);
    let create_db_sql = format!("CREATE DATABASE {};", SCHEMAMAP_DEV_DB);
    if let Some(c) = client {
        if let Err(e) = c.execute(&create_db_sql, &[]).await {
            log::warn!("Failed to create \"{}\" database: {}", SCHEMAMAP_DEV_DB, e);
            return Ok(());
        } else {
            let mut dev_pgconfig = pgconfig.clone();
            let dev_pgconfig_dbname = dev_pgconfig.dbname(&SCHEMAMAP_DEV_DB);

            let (schemamp_dev_c, connection) = dev_pgconfig_dbname.connect(NoTls).await?;

            tokio::spawn(async move {
                if let Err(e) = connection.await {
                    log::warn!("Connection error to \"schemamap_dev\" DB: {}", e);
                }
            });

            if let Err(e) = schemamp_dev_c.batch_execute(SCHEMAMAP_DEV_SQL).await {
                log::warn!("Failed to install dev extensions: {}", e);
            } else {
                log::info!("Installed dev extensions to \"{}\" DB", SCHEMAMAP_DEV_DB);
            }
        }
    } else {
        println!("{}", create_db_sql);
        println!("\\c schemamap_dev"); // assuming psql
        println!("{}", SCHEMAMAP_DEV_SQL);
    }

    Ok(())
}

pub async fn init(cli: &Cli, args: &InitArgs) -> Result<()> {
    let dry_run = args.dry_run.unwrap_or(false);

    log::info!("Initializing Schemamap.io Postgres SDK");

    // No reason to prompt for input if not interactive/TTY
    let interactive = atty::is(atty::Stream::Stdout) && args.input.unwrap_or(true);

    let pgconfig = initialize_pgconfig(cli, interactive);

    // Start by establishing a Postgres admin connection to DB
    let (client, connection) = if dry_run {
        (None, None)
    } else {
        match pgconfig.connect(NoTls).await {
            Ok(conn) => (Some(conn.0), Some(conn.1)),
            Err(e) => {
                log::error!("Postgres connection error: {}", e);
                log::error!("{:?}", pgconfig);

                println!("Alternatively, try running:\n");
                println!("schemamap init --dbname=postgres --dry-run | psql");
                std::process::exit(1);
            }
        }
    };

    connection.map(|c| {
        tokio::spawn(async move {
            if let Err(e) = c.await {
                log::error!("Postgres connection error: {}", e);
            }
        })
    });

    let dbname = pgconfig.get_dbname().unwrap_or("postgres").to_string();

    log::info!("Installing Schemamap.io Postgres SDK to DB: {}", dbname);

    create_schemamap_users(&dbname, &client).await?;

    set_search_path(&client).await?;

    grant_create_connect(&dbname, &client).await?;

    log::info!("Creating \"schemamap\" SDK schema in {}", dbname);

    create_schemamap_schema(&client).await?;

    log::info!(
        "Granting usage rights of \"schemamap\" schema in {}",
        dbname
    );

    grant_schemamap_usage(&pgconfig, &client).await?;

    log::info!("Schemamap.io Postgres SDK installed successfully");
    let dev_db_exists: bool = if let Some(c) = &client {
        c.query_one(
            "SELECT exists(select 1 from pg_database where datname = $1)",
            &[&SCHEMAMAP_DEV_DB],
        )
        .await?
        .get::<_, bool>(0)
    } else {
        false
    };

    let install_dev;
    if !dev_db_exists && interactive && args.dev.is_none() && !dry_run {
        install_dev = prompt_for_dev_installation();
    } else {
        install_dev = args.dev.unwrap_or(false);
    }

    if !dev_db_exists && install_dev {
        install_dev_extensions(&pgconfig, &client).await?;
    }

    Ok(())
}

fn theme() -> ColorfulTheme {
    ColorfulTheme::default()
}

fn prompt_for_dev_installation() -> bool {
    return dialoguer::Confirm::with_theme(&theme())
        .with_prompt("Do you want to install development-time extensions for DB snapshotting?")
        .default(true)
        .interact()
        .unwrap_or(false);
}

fn prompt_for_pg_connstring() -> String {
    dialoguer::Input::with_theme(&theme())
        .with_prompt("Please provide your local Postgres connection string with an admin role")
        .with_initial_text("postgres://postgres:postgres@localhost:5432/postgres")
        .interact_text()
        .unwrap()
}
