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
            The first match is the input name; the second one is the branch.
          */
          inputVersionRegex ? "^(flakever-(.+))$",

          /**
            The branch to look for. If there are no branches, will look for an input
            that looks like `flakever-version`.
          */
          branch ? "version",

          # The script name. You can override this to "version" for example.
          scriptName ? "flakever",

          # The date format.
          dateFormat ? "%+4Y%m%d",

          # The default date.
          defaultDate ? "20250101",

          # The number of seconds per nightly build.
          secondsPerNightly ? 86400,

          /**
            Max digits per version component, e.g. [ 2 2 2 3 ] for a maximum of 99.99.99.999.
            Versions above the threshold saturate.
            The default will not saturate.
            Providing this will generate versionCode.
          */
          digits ? [ ],
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
              versionTemplate = input.versionTemplate or null;
              lastModifiedDateTime = input.lastModifiedDate or "19700101000000";
              lastModifiedMatch = builtins.match "^([0-9]{8})([0-9]{6})$" lastModifiedDateTime;
              lastModifiedDate =
                if lastModifiedMatch == null then "19700101" else builtins.head lastModifiedMatch;
              lastModifiedTime =
                if lastModifiedMatch == null then "000000" else builtins.head (builtins.tail lastModifiedMatch);
            in
            rec {
              inherit versionTemplate;
              rev = input.rev or input.dirtyRev or "unknown";
              shortRev = input.shortRev or input.dirtyShortRev or (builtins.substring 0 8 rev);
              lastModified = input.lastModified or 0;
              inherit lastModifiedDate lastModifiedTime;
            };

          # The version info for self.
          selfVersionInfo = extractVersionFrom "self" inputs.self;

          # The version info: either the flake input corresponding to the branch, or self.
          versionInfo =
            if inputs.self.versionTemplate or null == null then
              let
                keys = builtins.map (builtins.match inputVersionRegex) (builtins.attrNames inputs);
                chosenKeys = builtins.filter (
                  match: match != null && builtins.head (builtins.tail match) == branch
                ) keys;
                chosenKey =
                  if builtins.length chosenKeys > 0 then builtins.head (builtins.head chosenKeys) else null;
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
              selfVersionInfo;

          # Handles constant placeholders in the version string.
          handleConstantPlaceholders =
            str:
            assert builtins.isString str;
            builtins.replaceStrings
              [ "<branch>" "<longRev>" "<rev>" "<lastModifiedDate>" "<lastModifiedTime>" ]
              [
                branch
                selfVersionInfo.rev
                selfVersionInfo.shortRev
                selfVersionInfo.lastModifiedDate
                selfVersionInfo.lastModifiedTime
              ]
              str;

          # Handles variable placeholders by replacing them with a (pure) default.
          handleVariablePlaceholders =
            str:
            builtins.replaceStrings [ "<date>" "<nightly>" ] [ defaultDate "0" ] (
              handleConstantPlaceholders str
            );

          # Computes base^exp iteratively.
          pow = base: exp: builtins.foldl' (s: x: s * base) 1 (builtins.genList (x: x) exp);

          # The version, with purifying substitutions made.
          version = handleVariablePlaceholders versionInfo.versionTemplate;

          # Splits the version (note that Nix semantics consider . and - identical, so we do it by hand).
          split = builtins.split "\\." version;
          splitVersion = builtins.genList (x: builtins.elemAt split (x * 2)) (builtins.length split / 2 + 1);

          # Picks the integers out from the start of each component.
          splitVersion' = builtins.map getInt splitVersion;

          # The number of version components.
          numComponents = builtins.length splitVersion';

          # 0 or missing in the digits list means unlimited.
          digits' = builtins.genList (
            x: if x >= builtins.length digits then 0 else builtins.elemAt digits x
          ) numComponents;

          # Returns true if the max digits are defined for each component of the version.
          canMakeVersionCode =
            builtins.length (builtins.filter (x: x > 0) digits') == builtins.length digits';

          # Reversed digits turned into factors for building the version code.
          # For instance, digits' of 1 2 3 4 becomes 1000 100 10 1.
          factors =
            if canMakeVersionCode then
              builtins.foldl' (s: x: s ++ [ (x * (builtins.elemAt s (builtins.length s - 1))) ]) [ 1 ] (
                builtins.genList (x: pow 10 (builtins.elemAt digits' (builtins.length digits' - x - 1))) (
                  builtins.length digits' - 1
                )
              )
            else
              [ ];

          # Matches a version component and some possible other stuff after it.
          getComponentMatch =
            componentStr:
            assert builtins.isString componentStr && builtins.stringLength componentStr > 0;
            let
              match = builtins.match "^([0-9]+)(.*)$" componentStr;
            in
            assert match != null;
            match;

          # Gets an integer at the start of a component string.
          getInt = componentStr: builtins.fromJSON (builtins.head (getComponentMatch componentStr));

          # Replaces an integer at the start of the specified version component string.
          replaceInt =
            componentStr: x:
            let
              match = getComponentMatch componentStr;
            in
            toString x + (builtins.head (builtins.tail match));

          # Creates a version component, saturating it at digits.
          makeComponent =
            component: digits: scale:
            let
              max = pow 10 digits - 1;
            in
            if max < 1 then
              component * scale
            else if component > max then
              max * scale
            else if component < 1 then
              0
            else
              component * scale;

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

              dateCmd=${pkgs.coreutils}/bin/date

              # Get the version and other constants.
              version=${lib.escapeShellArg (handleConstantPlaceholders versionInfo.versionTemplate)}
              version="''${VERSION:-$version}"
              lastModified=${lib.escapeShellArg (toString versionInfo.lastModified)}
              dateFormat=${lib.escapeShellArg dateFormat}
              secondsPerNightly=${lib.escapeShellArg (toString secondsPerNightly)}
              factors=(${lib.escapeShellArgs (map toString factors)})

              isImpure=0
              isCode=0
              noNewline=0
              while [ $# -gt 0 ]; do
                case "$1" in
                  -i|--impure)
                    isImpure=1
                    shift
                    ;;
                  -c|--code)
                    isCode=1
                    shift
                    ;;
                  -n|--no-newline)
                    noNewline=1
                    shift
                    ;;
                  -v|--version)
                    if [ $# -ge 2 ]; then
                      version="$2"
                    else
                      echo "No version provided" >&2
                    fi
                    shift; shift
                    ;;
                  -h|--help)
                    echo "Usage: $0 [-i|--impure] [-c|--code] [-n|--no-newline] [-v|--version] [-h|--help]" >&2
                    exit 1
                    ;;
                  *)
                    break
                    ;;
                esac
              done

              # Either echo or echo -n, depending on noNewline.
              puts() {
                if [ "$noNewline" -eq 0 ]; then
                  echo "$@"
                else
                  echo -n "$@"
                fi
              }

              # Get whether we are in impure mode or not.
              if [ "$isImpure" -eq 1 ]; then
                now="$EPOCHSECONDS"
              else
                now="$($dateCmd -u -d ${lib.escapeShellArg defaultDate} +%s)"
              fi

              # Get the number of components.
              components=0
              if [ $# -eq 1 ] && [[ "$1" =~ ^-?[0-9]+$ ]]; then
                components="$1"
              fi

              # Figure out the date.
              date="$($dateCmd -u -d "@$now" "+$dateFormat")"

              # Compute the nightly build number.
              if [ "$lastModified" -lt 1 ]; then
                lastModified="$now"
              fi

              diff=$((now - lastModified))
              if [ "$diff" -lt 1 ]; then
                diff=0
              fi
              nightly=$(((diff + secondsPerNightly - 1) / secondsPerNightly))

              # Adjust the requested number of components.
              IFS=. read -ra versionParts <<< "$version"
              numParts="''${#versionParts[@]}"
              if [ "$components" -le 0 ]; then
                components=$((numParts + components))
              fi
              if [ "$components" -lt 1 ]; then
                components=1
              elif [ "$components" -gt "$numParts" ]; then
                components="$numParts"
              fi

              # Build the new version.
              idx=0
              version=""
              versionPartCodes=()
              for part in "''${versionParts[@]}"; do
                if [ -n "$part" ]; then
                  # Substitute in the date, nightly build counter, and last-modified.
                  part="''${part//<date>/$date}"
                  part="''${part//<nightly>/$nightly}"

                  if [ "$isCode" -ne 0 ]; then
                    partCode=0
                    if [[ "$part" =~ ^([0-9]+) ]]; then
                      partCode="''${BASH_REMATCH[1]}"
                    fi
                    versionPartCodes+=("$partCode")
                  fi

                  if [ "$idx" -lt "$components" ]; then
                    version="$version$part"
                    if [ "$idx" -lt "$((components - 1))" ]; then
                      version="$version."
                    fi
                  fi
                  idx=$((idx + 1))
                fi
              done

              # Build the version code.
              versionCode=0
              if [ "$isCode" -ne 0 ] && [ "''${#factors[@]}" -gt 0 ] && [ "''${#factors[@]}" -eq "''${#versionPartCodes[@]}" ]; then
                for ((idx = 0; idx < components; idx++)); do
                  factor="''${factors[numParts - idx - 1]}"
                  partCode="''${versionPartCodes[idx]}"
                  versionCode=$((versionCode + factor * partCode))
                done
              else
                isCode=0
              fi

              if [ "$isCode" -eq 0 ]; then
                puts "$version"
              else
                puts "$version" >&2
                puts "$versionCode"
              fi
            '';

          /**
            A Nix version of flakever.
            Mostly just the result of calling mkFlakever.
            You can call this like a function to get pieces of the version.
          */
          nixFlakever = {
            # A functor that produces or removes the first or last n components of the version.
            __functor =
              self: n:
              let
                # Compute the number of elements we want.
                elems =
                  let
                    adjusted = if n <= 0 then numComponents + n else n;
                  in
                  if adjusted < 1 then
                    1
                  else if adjusted > numComponents then
                    numComponents
                  else
                    adjusted;

                # Build the version.
                version = builtins.concatStringsSep "." (
                  builtins.genList (
                    x:
                    replaceInt (builtins.elemAt splitVersion x) (
                      makeComponent (builtins.elemAt splitVersion' x) (builtins.elemAt digits' x) 1
                    )
                  ) elems
                );

                # And the version code.
                versionCode =
                  if canMakeVersionCode then
                    builtins.foldl' (s: x: s + x) 0 (
                      builtins.genList (
                        x:
                        (makeComponent (if x < elems then builtins.elemAt splitVersion' x else 0))
                          (builtins.elemAt digits' x)
                          (builtins.elemAt factors (builtins.length factors - x - 1))
                      ) numComponents
                    )
                  else
                    0;
              in
              {
                inherit version versionCode;
              };
          };
        in
        nixFlakever
        // {
          inherit versionInfo selfVersionInfo;

          # Make the full version and version code attributes accessible.
          inherit (nixFlakever 0) version versionCode;

          # Allow the bash version to be called like a functor too.
          script = bashFlakever // nixFlakever;
        };

      # In case of typos.
      lib.mkFlakeVer = throw "You meant: lib.mkFlakever";

      # And, of course, flakever itself has a flakever.
      versionTemplate = "0.3.0-<lastModifiedDate>";
      flakever = self.lib.mkFlakever {
        inherit inputs;
        digits = [
          1
          1
          1
        ];
      };

      inherit (self.flakever) version versionCode;
    };
}
