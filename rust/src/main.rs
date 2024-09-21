mod doctor;
mod init;
mod parsers;
mod up;

use anyhow::Result;
use clap::{Parser, Subcommand};

use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "schemamap")]
#[command(version = "0.4")]
#[command(
    about = "Instant batch data import for Postgres",
    long_about = r##"
  Schemamap.io uses the rich schema of your Postgres DB to infer data migrations/ETL.
  It takes care of data analysis, figuring out a data import function if possible and putting it in the staging tables.
  Then, it can import the data into the target tables, with the correct data types and constraints."##
)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Turn debugging information on
    #[arg(short('v'), long, action = clap::ArgAction::Count, help = "Make the operation more talkative", global = true)]
    verbose: u8,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    #[command(about = "Initialize the SDK in the given Postgres DB, idempotently")]
    Init(init::InitArgs),
    #[command(about = "Create a secure P2P tunnel to Schemamap.io.")]
    Up(up::UpArgs),
    #[command(about = "Check if the SDK is configured correctly")]
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
        Commands::Init(ref args) => args.dry_run.unwrap_or(false),
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
