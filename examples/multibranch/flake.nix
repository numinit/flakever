{
  description = "Flakever date-based versions with branches";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flakever.url = "../..";

    flakever-dev.url = "github:numinit/flakever-example-version/dev";
    flakever-main.url = "github:numinit/flakever-example-version/main";
    flakever-prod.url = "github:numinit/flakever-example-version/prod";
  };

  outputs =
    {
      self,
      flakever,
      nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      flakeverConfig = flakever.lib.mkFlakever {
        # Figures out your version template from the flake output.
        inherit inputs;

        # Active branch.
        branch = builtins.readFile ./BRANCH;

        # Max number of digits per component. Optional, but lets you make version codes.
        digits = [
          2
          2
          2
          3
        ];
      };
    in
    {
      packages.${system} = {
        versionTest = pkgs.stdenv.mkDerivation {
          pname = "version-test";
          inherit (flakeverConfig) version cleanVersion versionCode;

          dontUnpack = true;

          outputs = [
            "out"
            "clean"
            "code"
          ];

          installPhase = ''
            runHook preInstall
            echo $version > $out
            echo $cleanVersion > $clean
            echo $versionCode > $code
            runHook postInstall
          '';
        };
      };
    };
}
