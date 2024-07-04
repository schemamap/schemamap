use clap::{Args, Parser, Subcommand};

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

#[derive(Args)]
struct UpArgs {}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init(_args) => {
            println!("Init command...");
        }
        Commands::Up(_args) => {
            println!("Up command...");
        }
    }
}
