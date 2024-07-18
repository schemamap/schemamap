use clap::Parser;
use console::{style, Emoji};

use crate::parsers;

static LOOKING_GLASS: Emoji<'_, '_> = Emoji("🔍  ", "");

#[derive(Parser, Debug, Default, Clone)]
pub(crate) struct DoctorArgs {}

// Similar to doom doctor
pub(crate) async fn doctor(_args: DoctorArgs) -> anyhow::Result<()> {
    let pgconfig = parsers::parse_pgconfig(None, None, None, None)?;

    let (client, connection) = match pgconfig.connect(tokio_postgres::NoTls).await {
        Ok(c) => c,
        Err(e) => {
            log::error!("Failed to connect to database: {}", e);
            return Err(anyhow::anyhow!("Failed to connect to database: {}", e));
        }
    };

    tokio::spawn(async move {
        if let Err(e) = connection.await {
            log::error!("Postgres connection error: {}", e);
        }
    });

    println!(
        "{} {}Checking Schemamap SDK...",
        style("[1/4]").bold().dim(),
        LOOKING_GLASS
    );

    client.batch_execute("SELECT ").await?;
    Ok(())
}
