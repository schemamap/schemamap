use std::path::PathBuf;

use anyhow::Result;
use clap::{Args, Parser, Subcommand};
use tokio::{signal, sync::broadcast};
use tokio_postgres::NoTls;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "schemamap")]
#[command(version = "0.3")]
#[command(about = "Schemamap.io CLI", long_about = None)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Turn debugging information on
    #[arg(short, long, action = clap::ArgAction::Count)]
    debug: u8,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Init(InitArgs),
    Up(UpArgs),
    Doctor(DoctorArgs),
}

// Closely simulating psql cli arguments
#[derive(Args)]
struct InitArgs {
    #[arg(short, long, value_name = "USERNAME", help = "Superuser PG username")]
    username: Option<String>,

    #[arg(short, long, value_name = "DBNAME", help = "PG database name")]
    dbname: Option<String>,
}

#[derive(Parser, Debug, Default, Clone)]
struct UpArgs {
    #[arg(
        short,
        long,
        value_name = "FILE",
        help = "Secret tunnel configuration file path"
    )]
    file: Option<PathBuf>,
}

#[derive(Parser, Debug, Default, Clone)]
struct DoctorArgs {}

fn fallback_rathole_file_path() -> PathBuf {
    let path = directories::ProjectDirs::from("io", "schemamap", "schemamap-cli")
        .expect("Failed to get project directories")
        .config_dir()
        .join("rathole.toml");

    log::info!("Using default rathole file path: {:?}", path);

    PathBuf::from(path)
}

fn configure_logging(debug: bool) {
    #[cfg(feature = "console")]
    {
        console_subscriber::init();

        tracing::info!("console_subscriber enabled");
    }
    #[cfg(not(feature = "console"))]
    {
        let is_atty = atty::is(atty::Stream::Stdout);

        let level = if debug { "debug" } else { "info" }; // if RUST_LOG not present, use `info` level
        tracing_subscriber::fmt()
            .with_env_filter(
                EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::from(level)),
            )
            .with_ansi(is_atty)
            .init();
    }
}

async fn up(args: UpArgs) -> Result<()> {
    let rathole_file_path: PathBuf = args.file.unwrap_or_else(fallback_rathole_file_path);

    let args = rathole::Cli {
        config_path: Some(rathole_file_path),
        genkey: None,
        client: true,
        server: false,
    };
    let (shutdown_tx, shutdown_rx) = broadcast::channel::<bool>(1);

    tokio::spawn(async move {
        if let Err(e) = signal::ctrl_c().await {
            // Something really weird happened. So just panic
            panic!("Failed to listen for the ctrl-c signal: {:?}", e);
        }

        if let Err(e) = shutdown_tx.send(true) {
            // shutdown signal must be catched and handle properly
            // `rx` must not be dropped
            panic!("Failed to send shutdown signal: {:?}", e);
        }
    });

    log::info!("Starting P2P encrypted Postgres tunnel towards Schemamap.io...");

    rathole::run(args, shutdown_rx).await
}

async fn init(args: InitArgs) -> Result<()> {
    // Start by establishing a Postgres superuser admin connection to DB
    let (client, connection) = tokio_postgres::connect(
        &format!(
            "host=localhost user={} dbname={}",
            args.username.unwrap_or("postgres".to_string()),
            args.dbname.unwrap_or("postgres".to_string())
        ),
        NoTls,
    )
    .await?;

    tokio::spawn(async move {
        if let Err(e) = connection.await {
            log::error!("Postgres connection error: {}", e);
        }
    });

    log::info!("Result: {:?}", client.simple_query("SELECT 1").await?);

    Ok(())
}

async fn doctor(_args: DoctorArgs) -> Result<()> {
    // Similar to doom doctor
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    configure_logging(cli.debug > 0);

    match cli.command {
        Commands::Init(args) => init(args).await,
        Commands::Up(args) => up(args).await,
        Commands::Doctor(args) => doctor(args).await,
    }
}