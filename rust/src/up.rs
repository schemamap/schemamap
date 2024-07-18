use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;
use tokio::{signal, sync::broadcast};

#[derive(Parser, Debug, Default, Clone)]
pub(crate) struct UpArgs {
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

pub(crate) async fn up(args: UpArgs) -> Result<()> {
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
