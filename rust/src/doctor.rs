use lazy_static::lazy_static;
use std::{collections::HashSet, process::exit};

use clap::Parser;
use console::{style, Emoji};
use serde_json::to_string_pretty;

use crate::{parsers, up};

static LOOKING_GLASS: Emoji<'_, '_> = Emoji("🔍 ", "");
static CHECK: Emoji<'_, '_> = Emoji("✅ ", "");
static CROSS: Emoji<'_, '_> = Emoji("❌ ", "");
static LOCK: Emoji<'_, '_> = Emoji("🔒 ", "");

#[derive(Parser, Debug, Default, Clone)]
pub(crate) struct DoctorArgs {}

fn print_check(message: &str, check_result: bool) {
    if check_result {
        println!("{}{}", CHECK, style(message).green());
    }
}

async fn check_if_schemamap_schema_exists(client: &tokio_postgres::Client) -> anyhow::Result<bool> {
    let schemamap_schema_exists: bool = client
        .simple_query(
            "SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name = 'schemamap'
            LIMIT 1;",
        )
        .await?
        .get(0)
        .is_some();

    print_check("`schemamap` schema exists", schemamap_schema_exists);
    if !schemamap_schema_exists {
        println!(
            "{} Schemamap schema not found, please run `schemamap init` first.",
            CROSS
        );
        exit(1);
    }
    Ok(schemamap_schema_exists)
}

lazy_static! {
    static ref MUST_HAVE_ROLES: HashSet<&'static str> = HashSet::from([
        "schemamap_schema_read",
        "schemamap_readonly",
        "schemamap_readwrite",
        "schemamap",
    ]);
}

async fn check_schemamap_roles(client: &tokio_postgres::Client) -> anyhow::Result<bool> {
    let role_check_sql = "
  WITH RECURSIVE role_hierarchy AS (
    SELECT
        r.rolname AS role_name,
        r.oid AS role_oid,
        r.rolname AS member_of
    FROM
        pg_roles r
    WHERE
        r.rolname LIKE 'schemamap%'

    UNION ALL

    SELECT
        r.rolname AS role_name,
        m.roleid AS role_oid,
        r2.rolname AS member_of
    FROM
        pg_roles r
    JOIN
        pg_auth_members m ON r.oid = m.member
    JOIN
        pg_roles r2 ON m.roleid = r2.oid
    WHERE
        r.rolname LIKE 'schemamap%'
),
privileges_agg AS (
    SELECT
        r.role_name,
        g.table_schema AS table_schema,
        g.privilege_type AS privilege_type,
        COUNT(g.table_name) AS table_count
    FROM
        role_hierarchy r
    LEFT JOIN
        information_schema.role_table_grants g
        ON r.member_of = g.grantee AND
           g.table_schema IS NOT NULL AND
           g.privilege_type IS NOT NULL AND
           g.table_schema != 'schemamap'
    GROUP BY
        r.role_name, g.table_schema, g.privilege_type
),
json_agg_step AS (
    SELECT
        role_name,
        table_schema,
        jsonb_object_agg(
            privilege_type,
            table_count
        ) FILTER (WHERE privilege_type IS NOT NULL AND table_count IS NOT NULL)
          AS privileges_per_schema
    FROM
        privileges_agg
    GROUP BY
        role_name, table_schema
),
final_agg AS (
    SELECT
        role_name,
        jsonb_object_agg(
            table_schema,
            privileges_per_schema
        ) FILTER (WHERE table_schema IS NOT NULL AND privileges_per_schema IS NOT NULL) AS privileges
    FROM
        json_agg_step
    GROUP BY
        role_name
)
SELECT
    role_name,
    privileges
FROM
    final_agg
ORDER BY 1;";

    let resultset = client.query(role_check_sql, &[]).await?;
    println!(
        "{}",
        style(format!("{} Checking schemamap roles:", LOOKING_GLASS)).bold()
    );

    let mut seen_roles = HashSet::<String>::new();

    resultset.into_iter().for_each(|row| {
        let role_name: String = row.get("role_name");
        seen_roles.insert(role_name.clone());
        let privileges: Option<serde_json::Value> = row.get("privileges");

        let indent = "  ";
        println!("{}{} role: {}", indent, CHECK, role_name);
        match privileges {
            Some(privileges) => {
                println!("{}{} GRANTs by schema and type:", indent, LOCK);
                println!("{}{}", indent, to_string_pretty(&privileges).unwrap());
            }
            None => {}
        }
    });

    let seen_roles_str: HashSet<&str> = seen_roles.iter().map(|s| s.as_str()).collect();
    let missing_required_roles: Vec<String> = MUST_HAVE_ROLES
        .difference(&seen_roles_str)
        .map(|s| s.to_string())
        .collect();

    if missing_required_roles.is_empty() {
        println!("{} All required roles are present", CHECK);
    } else {
        println!("{} Missing required roles:", CROSS);
        for role in missing_required_roles {
            println!("  {}", role);
        }
    }

    Ok(true)
}

async fn check_if_tunnel_config_exists() -> anyhow::Result<bool> {
    let first_existing_filepath = up::find_first_existing_tunnel_config_file(&vec![None]);
    let file_exists = first_existing_filepath.is_some();

    if file_exists {
        print_check(
            format!(
                "Tunnel config exists at: {}",
                first_existing_filepath.unwrap().display()
            )
            .as_str(),
            file_exists,
        );
    } else {
        println!(
            "{} No tunnel config found, run `schemamap up` to create one.",
            CROSS
        );
        println!("  This will allow your local DB to receive data migrations from other environments and data sources.")
    }

    Ok(file_exists)
}

// Similar to `doom doctor`
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

    check_if_schemamap_schema_exists(&client).await?;

    check_schemamap_roles(&client).await?;

    check_if_tunnel_config_exists().await?;

    Ok(())
}
