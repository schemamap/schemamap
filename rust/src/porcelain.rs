use clap::Parser;
use tokio_postgres::Client;

use crate::{common::Cli, parsers};

#[derive(Parser, Debug, Default, Clone)]
pub struct StatusArgs {
    #[arg(long,
      help = "Refresh the SMO materialized view to reflect the current DB state.",
      default_value = "true",
      default_missing_value = "true",
      num_args =0..=1,
      action = clap::ArgAction::Set
  )]
    refresh: Option<bool>,
}

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

pub async fn status(cli: &Cli, args: &StatusArgs) -> anyhow::Result<()> {
    let client = connect(cli).await?;

    if let Some(refresh) = args.refresh {
        if refresh {
            log::info!("Refreshing schemamap.schema_metadata_overview");
            client
                .execute(
                    "select schemamap.update_schema_metadata_overview(concurrently := false)",
                    &[],
                )
                .await?;

            log::info!("Refreshed schemamap.schema_metadata_overview with latest DB state");
        }
    }

    let aggregate_summary = client
        .query_one(
            "select
                        count(distinct schema_name) as schema_count,
                        count(distinct (schema_name, table_name)) as table_count,
                        count(1) as column_count,
                        sum(case when is_pii then 1 else 0 end) as pii_count,
                        sum(case when is_metadata then 1 else 0 end) as metadata_count,
                        sum(case when is_schema_migration_table then 1 else 0 end) as schema_migration_table_count
                      from schemamap.smo",
            &[],
        )
        .await?;

    println!("Schema count: {}", aggregate_summary.get::<_, i64>(0));
    println!("Table count: {}", aggregate_summary.get::<_, i64>(1));
    println!("Column count: {}", aggregate_summary.get::<_, i64>(2));
    println!("PII column count: {}", aggregate_summary.get::<_, i64>(3));
    println!(
        "Metadata column count: {}",
        aggregate_summary.get::<_, i64>(4)
    );
    println!(
        "Schema migration table count: {}",
        aggregate_summary.get::<_, i64>(5)
    );

    Ok(())
}
