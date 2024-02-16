{ pkgs, config, ... }:

{
  process.implementation = "process-compose";

  processes.schemamap-cli.exec = "./schemamap.sh --help";
  enterShell = ''
    ln -sf ${config.process-managers.process-compose.configFile} ${config.env.DEVENV_ROOT}/process-compose.yml
  '';
}
