{ pkgs, version }:

pkgs.rustPlatform.buildRustPackage {
  pname = "schemamap";
  inherit version;

  src = pkgs.nix-gitignore.gitignoreSource [ ] ./rust;
  cargoLock.lockFile = ./rust/Cargo.lock;
  # cargoHash = "sha256-kxxjBIWUAkZSXP/N5wuJ9h/QGNGRuCMdelUsd/T0tkM=";

  buildInputs = [ pkgs.openssl ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk; [
    frameworks.Security
    frameworks.CoreFoundation
    frameworks.CoreServices
    frameworks.SystemConfiguration
  ]);

  nativeBuildInputs = [
    pkgs.pkg-config # needed for opennssl to be found on Linux
  ];

  meta = {
    description = "Schemamap.io CLI - Instant batch data import for Postgres";
    homepage = "https://github.com/schemamap/schemamap";
    license = pkgs.lib.licenses.mit;
    maintainers = [ pkgs.thenonameguy ];
  };
}
