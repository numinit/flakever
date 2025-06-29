{
  description = "Flakever date-based versions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flakever.url = "../..";
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

        # Max number of digits per component. Optional, but lets you make version codes.
        digits = [
          1
          2
          1
        ];
      };
    in
    {
      packages.${system} = {
        versionTest = pkgs.stdenv.mkDerivation {
          pname = "version-test";
          inherit (flakeverConfig) version versionCode;

          dontUnpack = true;

          outputs = [
            "out"
            "code"
          ];

          installPhase = ''
            runHook preInstall
            echo $version > $out
            echo $versionCode > $code
            runHook postInstall
          '';
        };
      };

      # lastModified substitutes the flake's last modified in impure mode
      versionTemplate = "1.2.3-<lastModifiedDate>";

      # nightly is the difference between the last modified flake input,
      # and the version input's last modified timestamp, converted to days (ceiling division)
      # versionTemplate = "1.2.<nightly>";

      # rev is 7 digits of git hash, or unknown
      # versionTemplate = "1.2.3-<rev>";
    };
}
