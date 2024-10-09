{ config, lib, pkgs, ... }:

# TODO: upstream to devenv.sh once stable
let
  cfg = config.services.schemamap;
in
{
  options.services.schemamap = {
    enable = lib.mkEnableOption "the Schemamap.io Postgres integration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.schemamap;
      defaultText = lib.literalExpression "pkgs.schemamap";
      description = "The Schemamap.io CLI package to use.";
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The Postgres rolename that is used for `schemamap init` (if null, the database specific role or $USER is used).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [ cfg.package ];

    processes = {
      schemamap-init = {
        exec =
          let
            initialDatabases = config.services.postgres.initialDatabases;
            # Initialize
            schemamap_commands = lib.concatMapStringsSep "\n"
              (init-db:
                let
                  user =
                    if cfg.user != null then
                      cfg.user
                    else if init-db ? user && init-db.user != null then
                      init-db.user
                    else "\${USER:-$(id -nu)}";
                in
                "${cfg.package}/bin/schemamap init --dbname=${init-db.name} --username=${user}"
              )
              initialDatabases;
          in
          schemamap_commands;
        process-compose = {
          description = "Idempotently initializes the Schemamap.io SDK in the local Postgres DB, with developer-mode extensions.";
          availability.restart = "never";
          depends_on = {
            postgres.condition = "process_healthy";
          };
        };
      };

      schemamap-up = {
        exec = "${cfg.package}/bin/schemamap up";
        process-compose = {
          description = "Establishes secure network tunnel between the local Postgres instance and Schemamap.io";
          availability.restart = "never";
          depends_on = {
            schemamap-init.condition = "process_completed_succesfully";
            postgres.condition = "process_healthy";
          };
        };
      };
    };
  };
}
