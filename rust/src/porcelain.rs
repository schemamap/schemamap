use clap::Parser;
use tokio_postgres::Client;

use crate::{common::Cli, parsers};

#[derive(Parser, Debug, Default, Clone)]
pub struct StatusArgs {
    #[arg(
      short('r'),
      long,
      help = "Refresh the SMO materialized view to reflect the current DB state.",
      default_value = "true",
      default_missing_value = "true",
      num_args =0..=1,
      action = clap::ArgAction::Set
  )]
    refresh: Option<bool>,

    #[arg(
      short('a'),
      long,
      help = "Return all schemamap.smo records as a JSON array.",
      default_missing_value = "true",
      default_value = "false",

      num_args =0..=1,
      action = clap::ArgAction::Set
  )]
    all: Option<bool>,
}

#[derive(Parser, Debug, Default, Clone)]
pub struct RefreshArgs {}

pub async fn connect(cli: &Cli) -> anyhow::Result<Client> {
    let pgconfig = parsers::parse_pgconfig_from_cli(cli)?;

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

    Ok(client)
}

async fn refresh_sql(client: &Client) -> anyhow::Result<()> {
    let refresh_sql = "select schemamap.update_schema_metadata_overview(concurrently := false)";

    log::info!("Refreshing schemamap.schema_metadata_overview");
    if let Err(e) = client.execute(refresh_sql, &[]).await {
        log::warn!(
            "Failed to refresh schemamap.schema_metadata_overview: {}",
            e
        );
        return Err(e.into());
    }

    log::info!("Refreshed schemamap.schema_metadata_overview with latest DB state");

    Ok(())
}

pub async fn refresh(cli: &Cli) -> anyhow::Result<()> {
    let client = connect(cli).await?;

    refresh_sql(&client).await?;

    Ok(())
}

pub async fn status(cli: &Cli, args: &StatusArgs) -> anyhow::Result<()> {
    let client = connect(cli).await?;

    if let Some(refresh) = args.refresh {
        if refresh {
            refresh_sql(&client).await?;
        }
    }

    let all = args.all.unwrap_or(false);

    let output = if all {
        client.query_one(
            "select jsonb_pretty(jsonb_agg(smo order by schema_name, table_name, column_name)) as smo_text
                from schemamap.smo as smo",
            &[],
        )
    } else {
        client.query_one(
            "select jsonb_pretty(to_jsonb(status)) as status_text
            from schemamap.status as status",
            &[],
        )
    }
    .await?;

    println!("{}", output.get::<_, String>(0));

    Ok(())
}
