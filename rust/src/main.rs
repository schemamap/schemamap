mod doctor;
mod init;
mod parsers;
mod up;

use anyhow::Result;
use clap::{Parser, Subcommand};

use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "schemamap")]
#[command(version = "0.3")]
#[command(about = "Schemamap.io CLI", long_about = None)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Turn debugging information on
    #[arg(short('v'), long, action = clap::ArgAction::Count, help = "Turn debugging information on, more v's for more verbosity")]
    verbose: u8,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Init(init::InitArgs),
    Up(up::UpArgs),
    Doctor(doctor::DoctorArgs),
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

        let level = if debug { "debug" } else { "info" };
        tracing_subscriber::fmt()
            .with_env_filter(
                EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::from(level)),
            )
            .with_ansi(is_atty)
            .init();
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    let dry_run = match cli.command {
        Commands::Init(ref args) => args.dry_run,
        Commands::Up(_) => false,
        Commands::Doctor(_) => false,
    };

    // In case of dry-run, we don't want to log at all, to not interfere with STDOUT/STDERR
    if !dry_run {
        configure_logging(cli.verbose > 0);
    }

    match cli.command {
        Commands::Init(args) => init::init(args).await,
        Commands::Up(args) => up::up(args).await,
        Commands::Doctor(args) => doctor::doctor(args).await,
    }
}
