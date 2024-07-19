use anyhow::Result;
use clap::Parser;
use std::{io::BufRead, path::PathBuf, process::exit};
use tokio::{signal, sync::broadcast};
use url::Url;
use url_open::open;

#[derive(Parser, Debug, Default, Clone)]
pub(crate) struct UpArgs {
    #[arg(
        short,
        long,
        value_name = "FILE",
        help = "Secret tunnel configuration file path"
    )]
    file: Option<PathBuf>,
}

fn personal_tunnel_file_path() -> PathBuf {
    PathBuf::from(format!(".schemamap-tunnel.{}.toml", whoami::username()))
}

fn fallback_paths() -> Vec<PathBuf> {
    vec![
        PathBuf::from(".schemamap-tunnel.toml"),
        personal_tunnel_file_path(),
        dirs::config_dir().unwrap().join("schemamap-tunnel.toml"),
        directories::ProjectDirs::from("io", "schemamap", "schemamap-cli")
            .expect("Failed to get project directories")
            .config_dir()
            .join("tunnel.toml"),
    ]
}

fn read_multiline_string_from_stdin() -> Result<String> {
    let stdin = std::io::stdin();
    let mut input = String::new();
    let mut lines = stdin.lock().lines();

    let mut empty_line_count = 0;

    while let Some(Ok(line)) = lines.next() {
        if line.trim().is_empty() {
            empty_line_count += 1;
            if empty_line_count == 2 {
                break;
            }
        } else {
            empty_line_count = 0;
        }
        input.push_str(&line);
        input.push('\n'); // Add newline character to preserve the original input format
    }

    let mut trimmed_input = input.trim_end().to_string();
    trimmed_input.push('\n');
    Ok(trimmed_input)
}

fn lookup_filepaths(extra_paths: &Vec<Option<PathBuf>>) -> Vec<PathBuf> {
    extra_paths
        .iter()
        .chain(
            fallback_paths()
                .iter()
                .map(|p| Some(p.clone()))
                .collect::<Vec<_>>()
                .iter(),
        )
        .filter_map(|p| p.clone())
        .collect()
}

pub(crate) fn find_first_existing_tunnel_config_file(
    extra_paths: &Vec<Option<PathBuf>>,
) -> Option<PathBuf> {
    lookup_filepaths(&extra_paths)
        .iter()
        .find(|p| {
            log::debug!(
                "Checking if tunnel config file exists: {}",
                p.to_path_buf().display()
            );
            p.exists()
        })
        .cloned()
}

pub(crate) async fn up(args: UpArgs) -> Result<()> {
    let extra_paths = vec![args.file.clone()].clone();
    let first_existing_filepath = find_first_existing_tunnel_config_file(&extra_paths).clone();

    let _ =
    first_existing_filepath
    .as_ref()

        .ok_or_else(|| {
          log::warn!("Couldn't find a tunnel config file in either of the following locations:");
          for p in lookup_filepaths(&extra_paths).iter() {
            log::warn!("  {}", p.to_path_buf().display());
          }
          if atty::is(atty::Stream::Stdout) {
            log::warn!("No existing tunnel config file found");
            log::info!("Once you have received your tunnel config content, paste it here.");
            log::info!("It will be saved to {}", personal_tunnel_file_path().display());
            log::info!("It's recommended to .gitignore this file, as it's your personal tunnel config within this project.\n");

            log::info!("Press enter to open the tunnel config creation page in your browser.");

            let _ = std::io::stdin().read_line(&mut String::new());
            open(&Url::parse("https://app.schemamap.io/").unwrap());
            println!("Paste the tunnel config here then press Enter a few times:");
            println!();

            // read from stdin a multiline string, containing the tunnel config
            let secret_tunnel_config = read_multiline_string_from_stdin().unwrap_or_else(|_| {
                log::warn!("Failed to read tunnel config from stdin, exiting.");
                exit(1);
            });

            println!();

            // write the tunnel config to the file
            std::fs::write(personal_tunnel_file_path(), secret_tunnel_config).unwrap();

            println!();

            log::info!("Tunnel config saved to {}", personal_tunnel_file_path().display());
            log::info!("Run `schemamap up` again to start the tunnel.");
            exit(0);
          } else {
            log::warn!("No existing tunnel config file found, go to https://app.schemamap.io/ to create one for this project's environment.");
            log::info!("For a more assisted setup, run `schemamap up` in your terminal and follow the instructions.");
            log::info!("Alternatively, provide the tunnel config content via the --file flag.");

            exit(1)
          }
        });

    let tunnel_file = first_existing_filepath.unwrap();
    let args = rathole::Cli {
        config_path: Some(tunnel_file.to_path_buf()),
        genkey: None,
        client: true,
        server: false,
    };
    let (shutdown_tx, shutdown_rx) = broadcast::channel::<bool>(1);

    tokio::spawn(async move {
        if let Err(e) = signal::ctrl_c().await {
            // Something really weird happened. So just panic
            panic!("Failed to listen for the ctrl-c signal: {:?}", e);
        }

        if let Err(e) = shutdown_tx.send(true) {
            // shutdown signal must be catched and handle properly
            // `rx` must not be dropped
            panic!("Failed to send shutdown signal: {:?}", e);
        }
    });

    log::info!(
        "Starting P2P encrypted Postgres tunnel towards Schemamap.io, using: {}",
        tunnel_file.display()
    );

    rathole::run(args, shutdown_rx).await
}
