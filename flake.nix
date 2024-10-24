{
  description = "Schemamap.io - Instant batch data import for Postgres";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs }:
    let
      version = "0.4.2";
      supportedSystems = [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: builtins.listToAttrs (map (name: { inherit name; value = f name; }) supportedSystems);
      mkPackage = pkgs: import ./package.nix { inherit pkgs version; };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = self.packages.${system}.schemamap;
          schemamap = mkPackage pkgs;
        });

      modules = [ ./schemamap.devenv.nix ];

      overlays.default = final: prev: {
        schemamap = self.packages.${prev.system}.schemamap;
      };
    };
}
