use clap::{Parser, Subcommand};

use crate::{doctor, init, porcelain, up};

#[derive(Parser)]
#[command(name = "schemamap")]
#[command(version = "0.4")]
#[command(
    about = "Instant batch data import for Postgres",
    long_about = r##"
  Schemamap.io uses the rich schema of your Postgres DB to infer data migrations/ETL.
  It takes care of data analysis, inferring an import function if possible, using unlogged tables.
  Then, it can import the data into the target tables, with the correct data types and constraints."##
)]
#[command(version, about, long_about = None)]
pub struct Cli {
    /// Turn debugging information on
    #[arg(short('v'), long, action = clap::ArgAction::Count, help = "Make the operation more talkative", global = true)]
    pub verbose: u8,

    #[arg(short('q'),
    long,
    action = clap::ArgAction::SetTrue,
     default_missing_value = "true",
     default_value = "false",
     help = "Only output to stdout, without logging",
     global = true)]
    pub quiet: Option<bool>,

    #[arg(
        short,
        long,
        value_name = "ADMIN-PSQL-CONNSTRING",
        help = "Administrator PG connection string. Can also be provided via DATABASE_URL environment variable.",
        long_help = "postgres://postgres:postgres@localhost:5432/postgres",
        global = true
    )]
    pub(crate) conn: Option<String>,

    #[arg(
        short,
        long,
        value_name = "USERNAME",
        help = "Admin PG username",
        global = true
    )]
    pub username: Option<String>,

    #[arg(
        short,
        long,
        value_name = "DBNAME",
        help = "PG database name",
        global = true
    )]
    pub dbname: Option<String>,

    #[arg(
        short,
        long,
        value_name = "PORT",
        help = "PG database port",
        global = true
    )]
    pub port: Option<u16>,

    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    #[command(about = "Initialize the SDK in the given Postgres DB, idempotently")]
    Init(init::InitArgs),
    #[command(about = "Create a secure P2P tunnel to Schemamap.io.")]
    Up(up::UpArgs),
    #[command(about = "Check if the SDK is configured correctly")]
    Doctor(doctor::DoctorArgs),
    #[command(about = "Get a high-level overview of the current DB state")]
    Status(porcelain::StatusArgs),
    #[command(about = "Refresh the SMO materialized view to reflect the current DB state")]
    Refresh(porcelain::RefreshArgs),
    #[command(about = "Snapshot the current DB to a new snapshot")]
    Snapshot(porcelain::SnapshotArgs),
    #[command(about = "Restore the current DB from a snapshot, destorying the current state")]
    Restore(porcelain::RestoreArgs),
}

pub const SCHEMAMAP_DEV_DB: &str = "schemamap_dev";
