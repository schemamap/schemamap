use std::path::PathBuf;

use anyhow::Result;
use clap::{Args, Parser, Subcommand};
use tokio::{signal, sync::broadcast};
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
}

#[derive(Args)]
struct InitArgs {}

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

fn fallback_rathole_file_path() -> PathBuf {
    let path = directories::ProjectDirs::from("io", "schemamap", "schemamap-cli")
        .expect("Failed to get project directories")
        .config_dir()
        .join("rathole.toml");

    log::info!("Using default rathole file path: {:?}", path);

    PathBuf::from(path)
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    #[cfg(feature = "console")]
    {
        console_subscriber::init();

        tracing::info!("console_subscriber enabled");
    }
    #[cfg(not(feature = "console"))]
    {
        let is_atty = atty::is(atty::Stream::Stdout);

        let level = "info"; // if RUST_LOG not present, use `info` level
        tracing_subscriber::fmt()
            .with_env_filter(
                EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::from(level)),
            )
            .with_ansi(is_atty)
            .init();
    }

    match cli.command {
        Commands::Init(_args) => {
            println!("Init command...");
            Ok(())
        }
        Commands::Up(args) => {
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
    }
}
