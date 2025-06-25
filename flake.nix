{
  description = "Provides nix and bash utilities to generate version numbers in a flake.";

  outputs =
    { self, ... }@inputs:
    {
      lib.mkFlakever =
        {
          /**
            The nixpkgs to use for building the version script. Optional, but useful
            if you'd like a version script.
          */
          pkgs ? null,

          /**
            The flake inputs.
          */
          inputs ? { },

          /**
            A regex for matching flake inputs that contain a version output.
          */
          inputVersionRegex ? "^flakever-(.+)",

          /**
            The branch to look for. If there are no branches, will look for an input
            that looks like `flakever-version`.
          */
          branch ? "version",

          # The script name. You can override this to "version" for example.
          scriptName ? "flakever",

          # The date format.
          dateFormat ? "%+4Y%m%d",

          # The number of seconds per nightly build.
          secondsPerNightly ? 86400,
        }:
        let
          /**
            Extracts version information from the specified flake info.
            @param chosenKey the key
            @param input the flake input
          */
          extractVersionFrom =
            chosenKey: input:
            let
              versionTemplate =
                input.versionTemplate or (throw ''
                  Input '${chosenKey}' does not have the output 'versionTemplate'.
                '');
            in
            assert builtins.isString input.versionTemplate;
            rec {
              rev = input.rev or input.dirtyRev or "unknown";
              shortRev = input.shortRev or input.dirtyShortRev or builtins.substring 0 8 rev;
              lastModified = input.lastModified or 0;
              inherit versionTemplate;
            };

          # The version info: either the flake input corresponding to the branch, or self.
          versionInfo =
            if inputs.self.versionTemplate or null == null then
              let
                keys = builtins.map (attr: builtins.match attr inputVersionRegex) (builtins.attrNames inputs);
                chosenKeys = builtins.filter (match: match != null && builtins.head match == branch) keys;
                chosenKey = if builtins.length chosenKeys > 0 then builtins.head chosenKeys else null;
                input = inputs.${chosenKey} or null;
              in
              if chosenKey == null || input == null then
                throw ''
                  You are missing a flake input with name '${branch}' matching the regex
                  ${inputVersionRegex}. Make sure that it's defined, or else override the version
                  by using `{ versionTemplate = "1.2.3"; }` on self.
                ''
              else
                extractVersionFrom chosenKey input
            else
              extractVersionFrom "self" inputs.self;

          # Handles constant placeholders in the version string.
          handleConstantPlaceholders =
            builtins.replaceStrings
              [ "<longRev>" "<rev>" ]
              [ versionInfo.rev versionInfo.shortRev ];

          # Handles variable placeholders by replacing them with a (pure) default.
          # Note that last-modified would require purely converting a UNIX timestamp to a date in Nix.
          # Contributions welcome...
          handleVariablePlaceholders =
            str:
            builtins.replaceStrings [ "<date>" "<nightly>" "<lastModified>" ] [ "20250101" "0" "19700101" ] (
              handleConstantPlaceholders str
            );

          /**
            A derivation building to a shell script that, when executed,
            prints the version up to the number of components specified in $1.
            You can specify --impure (-i) as the first argument to use the current timestamp.

            Specify a negative number of components to omit that many trailing version components.
          */
          bashFlakever =
            let
              inherit (pkgs) lib;
            in
            assert pkgs != null;
            pkgs.writeShellScriptBin scriptName ''
              set -euo pipefail

              # Get whether we are in impure mode or not.
              if [ $# -gt 0 ] && { [ "$1" == '-i' ] || [ "$1" == '--impure' ]; }; then
                shift
                now="$EPOCHSECONDS"
              else
                # 2025-01-01T00:00:00Z
                now=1735689600
              fi

              # Get the number of components.
              components=0
              if [ $# -eq 1 ] && [[ "$1" =~ ^-?[0-9]+$ ]]; then
                components="$1"
              fi

              # Get the version and other constants.
              version=${lib.escapeShellArg (handleConstantPlaceholders versionInfo.versionTemplate)}
              version="''${VERSION:-$version}"
              lastModified=${lib.escapeShellArg (toString versionInfo.lastModified)}
              dateFormat=${lib.escapeShellArg dateFormat}
              secondsPerNightly=${lib.escapeShellArg (toString secondsPerNightly)}
              nightlyOffset=1

              # Figure out the date and last-modified date.
              date="$(${pkgs.coreutils}/bin/date -u -d "@$now" "+$dateFormat")"
              lastModifiedDate="$(${pkgs.coreutils}/bin/date -u -d "@$lastModified" "+$dateFormat")"

              # Compute the nightly build number.
              if [ "$lastModified" -lt 1 ]; then
                lastModified="$now"

                # Same behavior as the pure version.
                nightlyOffset=0
              fi

              diff=$((now - lastModified))
              if [ "$diff" -lt 1 ]; then
                diff=0
              fi
              nightly=$((diff / secondsPerNightly + nightlyOffset))

              # Adjust the requested number of components.
              IFS=. read -ra versionParts <<< "$version"
              numParts="''${#versionParts[@]}"
              if [ "$components" -le 0 ]; then
                components=$((numParts + components))
              fi
              if [ "$components" -lt 0 ]; then
                components=1
              elif [ "$components" -gt "$numParts" ]; then
                components="$numParts"
              fi

              # Build the new version.
              version=""
              idx=0
              for part in "''${versionParts[@]}"; do
                if [ -n "$part" ]; then
                  version="$version$part"
                  idx=$((idx + 1))
                  if [ "$idx" -ge "$components" ]; then
                    break
                  else
                    version="$version."
                  fi
                fi
              done

              # Substitute in the date, nightly build counter, and last-modified.
              version="''${version//<date>/$date}"
              version="''${version//<nightly>/$nightly}"
              version="''${version//<lastModified>/$lastModifiedDate}"
              echo -n "$version"
            '';

          /**
            A Nix version of flakever.
            Mostly just the result of calling mkFlakever.
            You can call this like a function to get pieces of the version.
          */
          nixFlakever = {
            # The version, with purifying substitutions made.
            version = handleVariablePlaceholders versionInfo.versionTemplate;

            /**
              The version info.
              Contains rev, shortRev (default unknown) lastModified (default 0), and versionTemplate.
            */
            inherit versionInfo;

            # A functor that produces or removes the first or last n components of the version.
            __functor =
              self: n:
              let
                split = builtins.split "\\." self.version;
                splitVersion = builtins.genList (x: builtins.elemAt split (x * 2)) (builtins.length split / 2 + 1);
                splitVersion' = builtins.filter (
                  x: builtins.isString x && builtins.stringLength x > 0
                ) splitVersion;
                elems =
                  let
                    components = builtins.length splitVersion';
                    adjusted = if n <= 0 then components + n else n;
                  in
                  if adjusted < 0 then
                    1
                  else if adjusted > components then
                    components
                  else
                    adjusted;
              in
              builtins.concatStringsSep "." (builtins.genList (builtins.elemAt splitVersion') elems);
          };
        in
        nixFlakever
        // {
          # Allow the bash version to be called like a functor too.
          script = bashFlakever // nixFlakever;
        };

      # In case of typos.
      lib.mkFlakeVer = throw "You meant: lib.mkFlakever";

      # And, of course, flakever itself has a flakever.
      versionTemplate = "0.2.0-<lastModified>";
      flakever = self.lib.mkFlakever {
        inherit inputs;
      };

      inherit (self.flakever) version;
    };
}
