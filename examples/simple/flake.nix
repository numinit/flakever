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
    in
    {
      flakever = flakever.lib.mkFlakever {
        # Figures out your version template from the flake output.
        inherit inputs;

        # This is optional and gets you the script.
        inherit pkgs;

        # The default is `flakever` but you can change it.
        scriptName = "version";

        # Max number of digits per component. Optional, but lets you make version codes.
        digits = [
          1
          2
          1
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

      # date substitutes 20250101 in pure mode, or the current date in impure mode
      versionTemplate = "1.2.3-<date>";

      # lastModified substitutes 19700101 in pure mode, or the flake's last modified in impure mode
      # versionTemplate = "1.2.3-<lastModified>";

      # nightly is 0 in pure mode, or the difference between the current timestamp
      # and the version input's last modified timestamp, converted to days (ceiling division)
      # versionTemplate = "1.2.<nightly>";

      # rev is 8 digits of git hash, or unknown
      # versionTemplate = "1.2.3-<rev>";
    };
}
