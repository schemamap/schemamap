{ pkgs, lib, ... }:

{
  packages =
    with pkgs; [
      flyway.out
      shellcheck
      nix-output-monitor
      shfmt
      nixpkgs-fmt
      (pkgs.callPackage ./devenv/create-flyway-migration.nix { })
    ];

  languages = {
    clojure.enable = true;
    java.enable = true;
  };

  process.implementation = "process-compose";

  # https://devenv.sh/reference/options/#servicespostgresenable
  services.postgres = {
    enable = true;
    package = pkgs.postgresql_15;
    extensions = extensions: [ ];
    initdbArgs = [
      "--locale=C"
      "--encoding=UTF8"
    ];
    initialDatabases = [
      { name = "schemamap_test"; }
    ];

    initialScript = ''
      create user schemamap_test with password 'schemamap_test';
      grant all privileges on database schemamap_test to postgres;
      alter database schemamap_test owner to schemamap_test;

      create role schemamap with
        login
        nosuperuser
        nocreatedb
        nocreaterole
        noinherit
        noreplication
        connection limit 5
        encrypted password 'schemamap';

      grant connect, create on database schemamap_test to schemamap;
    '';

    listen_addresses = "127.0.0.1,localhost";

    port = 5432;
    # https://www.postgresql.org/docs/11/config-setting.html#CONFIG-SETTING-CONFIGURATION-FILE
    settings = {
      max_connections = 500;
      work_mem = "20MB";
      log_error_verbosity = "TERSE";
      log_min_messages = "NOTICE";
      log_min_error_statement = "WARNING";
      log_line_prefix = "%m [%p] %u@%d/%a";
      shared_preload_libraries = "pg_stat_statements";
      statement_timeout = "100s";
      deadlock_timeout = 3000;
      # maximize speed
      fsync = "off";
      jit = "0";
      synchronous_commit = "off";
    };
  };

  scripts = {
    psql-local.exec = "psql -h 127.0.0.1 -U schemamap_test schemamap_test $@";
    psql-local-smio.exec = "psql -h 127.0.0.1 -U schemamap schemamap_test $@";
    pgclear.exec = "git clean -xf $PGDATA";
  };

  pre-commit.hooks = {
    nixpkgs-fmt.enable = true;
    shellcheck.enable = true;
  };
}
