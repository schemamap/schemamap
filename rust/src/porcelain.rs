use clap::Parser;
use tokio_postgres::{Client, Config};

use crate::{
    common::{Cli, SCHEMAMAP_DEV_DB},
    parsers,
};

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

pub async fn connect_from_config(config: &Config) -> anyhow::Result<Client> {
    let (client, connection) = match config.connect(tokio_postgres::NoTls).await {
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

pub async fn connect(cli: &Cli) -> anyhow::Result<Client> {
    let pgconfig = parsers::parse_pgconfig_from_cli(cli)?;

    connect_from_config(&pgconfig).await
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

#[derive(Parser, Debug, Default, Clone)]
pub struct RefreshArgs {}

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

pub async fn connect_to_schemamap_dev(cli: &Cli) -> anyhow::Result<Client> {
    let mut pgconfig = parsers::parse_pgconfig_from_cli(cli)?;

    pgconfig.dbname(SCHEMAMAP_DEV_DB);

    connect_from_config(&pgconfig).await
}

#[derive(Parser, Debug, Default, Clone)]
pub struct SnapshotArgs {
    #[arg(
        long("from"),
        help = "The name of the database to snapshot, defaulting to the DB of the connection string"
    )]
    pub template_db_name: Option<String>,
    pub snapshot_name: Option<String>,
}

struct GitStats {
    branch_name: String,
    revision: String,
}

fn current_git_stats() -> anyhow::Result<GitStats> {
    let repo = git2::Repository::discover(".")?;
    let head = repo.head()?;
    let branch_name = head
        .shorthand()
        .ok_or_else(|| anyhow::anyhow!("Unable to determine branch name"))?
        .to_string();
    let revision = head
        .target()
        .ok_or_else(|| anyhow::anyhow!("Unable to determine revision"))?
        .to_string();

    Ok(GitStats {
        branch_name,
        revision,
    })
}

pub async fn snapshot(cli: &Cli, args: &SnapshotArgs) -> anyhow::Result<()> {
    let pgconfig = parsers::parse_pgconfig_from_cli(cli)?;

    let mut dev_pgconfig = pgconfig.clone();
    dev_pgconfig.dbname(SCHEMAMAP_DEV_DB);

    let client = connect_from_config(&dev_pgconfig).await?;

    let template_db_name = args.template_db_name.as_ref().map_or_else(
        || {
            pgconfig
                .get_dbname()
                .unwrap_or_else(|| "postgres")
                .to_string()
        },
        |name| name.clone(),
    );
    let git_stats = current_git_stats().unwrap_or_else(|_| GitStats {
        branch_name: "unknown".to_string(),
        revision: "unknown".to_string(),
    });

    let new_db_name = args.snapshot_name.as_ref().map_or_else(
        || format!("{}_{}", template_db_name, git_stats.branch_name),
        |name| name.clone(),
    );

    client
        .execute(
            "select create_snapshot($1, $2)",
            &[&template_db_name, &new_db_name],
        )
        .await?;

    client
        .execute(
            "update snapshots set git_branch = $1, git_rev = $2 where db_name = $3",
            &[&git_stats.branch_name, &git_stats.revision, &new_db_name],
        )
        .await?;

    Ok(())
}
