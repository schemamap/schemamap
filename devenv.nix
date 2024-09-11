{ pkgs, config, lib, inputs, ... }:

let postgres = pkgs.postgresql_15;
in {
  # TODO: remove once upstreamed to devenv.sh + nixpkgs
  imports = [ ./schemamap.devenv.nix ];

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
    jq
    (pkgs.callPackage ./devenv/create-flyway-migration.nix { })
  ] ++ lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk; [
    frameworks.Security
    frameworks.CoreFoundation
    frameworks.CoreServices
    frameworks.SystemConfiguration
  ]);

  languages = {
    clojure.enable = true;
    java.enable = true;
    rust = {
      enable = true;
      components = [ "rustc" "cargo" "clippy" "rustfmt" "rust-analyzer" ];
    };
  };

  # For stacktraces when things go wrong
  env.RUST_BACKTRACE = "1";

  process.implementation = "process-compose";

  services = {
    schemamap = {
      enable = true;
      # use local schemamap
      # TODO: adopt public cachix to not rebuild all the time in CI
      package = pkgs.callPackage ./package.nix { version = "dev"; };
    };

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

    # Needed so postgres can be restarted until the below issue is fixed:
    # https://github.com/F1bonacc1/process-compose/issues/200
    sleepy-keepalive.exec = "sleep infinity";
  };

  scripts = {
    psql-local.exec = "psql -h 127.0.0.1 -U schemamap_test schemamap_test $@";
    psql-local-smio.exec = "psql -h 127.0.0.1 -U schemamap schemamap_test $@";
    pgclear.exec = ''
      cd "$DEVENV_ROOT"
      process-compose process stop postgres
      sleep 1 # blocking versions of above would be nice
      git clean -xf "$PGDATA"
      process-compose process start postgres
      sleep 1 # allow postgres to init & become healthy
      # process-compose process start seed-postgres
    '';
    ci-test.exec = "process-compose --tui=false up -f process-compose.yml -f process-compose.test.yml";
  };

  enterShell = ''
    ln -sf ${config.process-managers.process-compose.configFile} ${config.env.DEVENV_ROOT}/process-compose.yml
    export PATH="$DEVENV_ROOT/bin:$PATH"
  '';

  pre-commit.hooks = {
    cljfmt = {
      enable = true;
      name = "cljfmt";
      description = "A tool for formatting Clojure code";
      entry = "${pkgs.cljfmt}/bin/cljfmt fix";
      types_or = [ "clojure" "clojurescript" "edn" ];
    };
    # TODO: figure out subfolder-based formatting properly
    # rustfmt = {
    #   enable = true;
    #   entry = lib.mkForce "${pkgs.rustfmt}/bin/cargo-fmt fmt -- --check --manifest-path rust/Cargo.toml";
    # };
    actionlint.enable = false; # for .github/workflows
    editorconfig-checker = {
      enable = true;
      # NOTE: .clj files have dynamic indentation, disable check
      entry = lib.mkForce
        "${pkgs.editorconfig-checker}/bin/editorconfig-checker --disable-indent-size";
    };
    nixpkgs-fmt.enable = true;
    shellcheck.enable = true;

    recreate-schemamap-schema-sql = {
      enable = true;
      name = "recreate-schemamap-schema-sql";
      entry = "./bin/recreate-schemamap-schema-sql.sh";
      types = [ "sql" ];
      verbose = true;
      pass_filenames = false;
    };
  };
}
