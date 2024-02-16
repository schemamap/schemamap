{ pkgs, config, lib, ... }:

let postgres = pkgs.postgresql_15;
in {
  packages = with pkgs; [
    flyway.out
    shellcheck
    nix-output-monitor
    shfmt
    nixpkgs-fmt
    cljfmt
    git-lfs
    just
    zstd
    (pkgs.callPackage ./devenv/create-flyway-migration.nix { })
  ];

  languages = {
    clojure.enable = true;
    java.enable = true;
  };

  process.implementation = "process-compose";

  services = {
    # https://devenv.sh/reference/options/#servicespostgresenable
    postgres = {
      enable = true;
      package = postgres;
      extensions = extensions: [ ];
      initdbArgs = [ "--locale=C" "--encoding=UTF8" ];
      initialDatabases = [{ name = "schemamap_test"; }];

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
  };

  processes = {
    # idempotently loads the Adventureworks sample DB
    # Use `pgclear && devenv up` to recreate from scratch
    seed-postgres = {
      exec = ''
        ${pkgs.zstd}/bin/zstd -dc db_dumps/Adventureworks.sql.zst | \
           ${postgres}/bin/psql -h 127.0.0.1 -U schemamap_test -v ON_ERROR_STOP=1 --single-transaction schemamap_test
      '';
      process-compose = {
        availability.restart = "no";
        depends_on.postgres.condition = "process_healthy";
      };
    };

    # override CWD of bash devenv process so it runs in the correct folder
    schemamap-cli.process-compose.working_dir = "bash";
  };

  scripts = {
    psql-local.exec = "psql -h 127.0.0.1 -U schemamap_test schemamap_test $@";
    psql-local-smio.exec = "psql -h 127.0.0.1 -U schemamap schemamap_test $@";
    pgclear.exec = "git clean -xf $PGDATA";
    ci-test.exec = "process-compose --tui=false up -f process-compose.yml -f process-compose.test.yml";
  };

  enterShell = ''
    ln -sf ${config.process-managers.process-compose.configFile} ${config.env.DEVENV_ROOT}/process-compose.yml
  '';

  pre-commit.hooks = {
    cljfmt = {
      enable = true;
      name = "cljfmt";
      description = "A tool for formatting Clojure code";
      entry = "${pkgs.cljfmt}/bin/cljfmt fix";
      types_or = [ "clojure" "clojurescript" "edn" ];
    };
    editorconfig-checker = {
      enable = true;
      # NOTE: .clj files have dynamic indentation, disable check
      entry = lib.mkForce
        "${pkgs.editorconfig-checker}/bin/editorconfig-checker --disable-indent-size";
    };
    nixpkgs-fmt.enable = true;
    shellcheck.enable = true;
  };
}
