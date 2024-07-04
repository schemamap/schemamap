{ pkgs, version }:

pkgs.rustPlatform.buildRustPackage {
  pname = "schemamap";
  inherit version;

  src = pkgs.lib.cleanSource ./rust;
  cargoLock.lockFile = ./rust/Cargo.lock;

  buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk; [
    frameworks.Security
    frameworks.CoreFoundation
    frameworks.CoreServices
    frameworks.SystemConfiguration
  ]);

  meta = {
    description = "Schemamap.io CLI - Postgres Data Movement";
    homepage = "https://github.com/schemamap/schemamap";
    license = pkgs.lib.licenses.mit;
    maintainers = [ pkgs.thenonameguy ];
  };
}
