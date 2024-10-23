mod common;
mod doctor;
mod init;
mod parsers;
pub mod porcelain;
mod up;

use anyhow::Result;

use clap::Parser;
use common::{Cli, Commands};
use tracing_subscriber::EnvFilter;

fn configure_logging(debug: bool) {
    #[cfg(feature = "console")]
    {
        console_subscriber::init();

        tracing::info!("console_subscriber enabled");
    }
    #[cfg(not(feature = "console"))]
    {
        let is_atty = atty::is(atty::Stream::Stdout);

        let level = if debug { "debug" } else { "info" };
        tracing_subscriber::fmt()
            .with_env_filter(
                EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::from(level)),
            )
            .with_ansi(is_atty)
            // log to stderr to allow tooling to use stdout (example for `schemamap status` to pipe into jq)
            .with_writer(std::io::stderr)
            .init();
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // In case of dry-run, we don't want to log at all, to not interfere with STDOUT/STDERR
    let dry_run = match cli.command {
        Commands::Init(ref args) => args.dry_run.unwrap_or(false),
        _ => false,
    };

    let quiet = cli.quiet.unwrap_or(false);

    if !quiet && !dry_run {
        configure_logging(cli.verbose > 0);
    }

    match cli.command {
        Commands::Init(ref args) => init::init(&cli, args).await,
        Commands::Up(args) => up::up(args).await,
        Commands::Doctor(ref args) => doctor::doctor(&cli, args).await,
        Commands::Status(ref args) => porcelain::status(&cli, args).await,
        Commands::Refresh(_) => porcelain::refresh(&cli).await,
        Commands::Snapshot(ref args) => porcelain::snapshot(&cli, args).await,
        Commands::Restore(ref args) => porcelain::restore(&cli, args).await,
        Commands::List(ref args) => porcelain::list(&cli, args).await,
    }
}
