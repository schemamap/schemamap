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
  };

  config = lib.mkIf cfg.enable {
    packages = [ cfg.package ];

    processes = {
      schemamap-init = {
        exec = "${cfg.package}/bin/schemamap init --dev --input=false";
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
