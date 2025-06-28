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
    in
    {
      flakever = flakever.lib.mkFlakever {
        # Figures out your version template from the flake output.
        inherit inputs;

        # This is optional and gets you the script.
        inherit pkgs;

        # Active branch.
        branch = builtins.readFile ./BRANCH;

        # The default is `flakever` but you can change it.
        scriptName = "version";

        # Max number of digits per component. Optional, but lets you make version codes.
        digits = [
          2
          2
          2
          3
        ];
      };

      packages.${system} = {
        version = self.flakever.script;

        # The version script is pure by default.
        versionTest = pkgs.stdenv.mkDerivation {
          pname = "version-test";
          inherit (self.flakever) version;

          nativeBuildInputs = [ self.flakever.script ];

          dontUnpack = true;

          outputs = [
            "out"
            "code"
          ];

          installPhase = ''
            runHook preInstall
            version -c >$code 2>$out
            runHook postInstall
          '';
        };

        # However, you can also make it impure, where
        # <date> will be substituted with the current date.
        versionTestImpure = pkgs.stdenv.mkDerivation {
          pname = "version-test-impure";
          inherit (self.flakever) version;

          nativeBuildInputs = [ self.flakever.script ];

          dontUnpack = true;

          outputs = [
            "out"
            "code"
          ];

          installPhase = ''
            runHook preInstall
            version -i -c 2>$out >$code
            runHook postInstall
          '';
        };
      };
    };
}
