{
  description = "Provides nix and bash utilities to generate version numbers in a flake.";

  outputs =
    { self, ... }@inputs:
    {
      lib.mkFlakever =
        with builtins;
        {
          /**
            Max digits per version component, e.g. [ 2 2 2 3 ] for a maximum of 99.99.99.999.
            Versions above the threshold saturate.
            The default will not saturate.
            Providing this will generate versionCode.
          */
          digits ? [ ],

          /**
            The flake inputs.
          */
          inputs ? { },

          /**
            A regex for matching flake inputs that contain a version output.
            The first match is the input name.
          */
          inputVersionRegex ? "^flakever-(.+)$",

          /**
            True if we should use all inputs to compute the "real" last-modified commit.
            False if we should just use self. The default is false so we only change the
            version if the source tree changes, which may cause a rebuild anyway.
          */
          useAllInputs ? false,

          /**
            The branch to look for. If there are no branches, will look for an input
            that looks like `flakever-version`.
          */
          branch ? "version",

          /**
            The number of seconds of difference in last-modified timestamp per nightly build.
          */
          secondsPerNightly ? 86400,
        }:
        let
          /**
            Extracts version information from the specified flake info.
            @param input the flake input
          */
          extractVersionFrom =
            input:
            let
              versionTemplate = input.versionTemplate or null;
              lastModifiedDateTime = input.lastModifiedDate or "19700101000000";
              lastModifiedMatch = match "^([0-9]{8})([0-9]{6})$" lastModifiedDateTime;
              lastModifiedDate = if lastModifiedMatch == null then "19700101" else head lastModifiedMatch;
              lastModifiedTime = if lastModifiedMatch == null then "000000" else head (tail lastModifiedMatch);
            in
            rec {
              inherit versionTemplate;
              rev = input.rev or input.dirtyRev or "unknown";
              shortRev = input.shortRev or input.dirtyShortRev or (substring 0 8 rev);
              lastModified = input.lastModified or 0;
              inherit lastModifiedDate lastModifiedTime;
            };

          # Match all input keys against the regex.
          allInputs = map (name: {
            inherit name;
            match = builtins.match inputVersionRegex name;
            input = inputs.${name};
          }) (attrNames inputs);

          # Choose ones that match the branch.
          branchInputVersionInfos = map (inputInfo: extractVersionFrom inputInfo.input) (
            filter (inputInfo: inputInfo.match != null && head inputInfo.match == branch) allInputs
          );

          # And get the first.
          branchInputVersionInfo =
            if length branchInputVersionInfos > 0 then head branchInputVersionInfos else null;

          # These don't match the branch.
          notBranchInputVersionInfos =
            if useAllInputs then
              map (inputInfo: extractVersionFrom inputInfo.input) (
                filter (inputInfo: inputInfo.match == null) allInputs
              )
            else
              [ selfVersionInfo ];

          # The version info corresponding to the latest input.
          latestInputVersionInfo = foldl' (
            s: x: if s == null || x.lastModified > s.lastModified then x else s
          ) null notBranchInputVersionInfos;

          # The version info for self.
          selfVersionInfo = extractVersionFrom inputs.self;

          # The version info: either the flake input corresponding to the branch, or self.
          versionInfo =
            if selfVersionInfo.versionTemplate or null == null then
              if branchInputVersionInfo == null then
                throw ''
                  You are missing a flake input with name '${branch}' matching the regex
                  ${inputVersionRegex}. Make sure that it's defined, or else override the version
                  by using `{ versionTemplate = "1.2.3"; }` on self.
                ''
              else
                branchInputVersionInfo
            else
              selfVersionInfo;

          # Ceiling division of the difference between the latest last-modified date
          # and the version's last-modified date
          nightly =
            if versionInfo == selfVersionInfo then
              0
            else
              assert latestInputVersionInfo != null;
              (latestInputVersionInfo.lastModified - versionInfo.lastModified + secondsPerNightly - 1)
              / secondsPerNightly;

          # Handles constant placeholders in the version string.
          handlePlaceholders =
            str:
            assert isString str;
            replaceStrings
              [ "<branch>" "<longRev>" "<rev>" "<lastModifiedDate>" "<lastModifiedTime>" "<nightly>" ]
              [
                branch
                selfVersionInfo.rev
                selfVersionInfo.shortRev
                selfVersionInfo.lastModifiedDate
                selfVersionInfo.lastModifiedTime
                (toString nightly)
              ]
              str;

          # Computes base^exp iteratively.
          pow = base: exp: foldl' (s: x: s * base) 1 (genList (x: x) exp);

          # Gets an integer at the start of a component string.
          getInt = componentStr: fromJSON (head (getComponentMatch componentStr));

          # Splits the version (note that Nix semantics consider . and - identical, so we do it by hand).
          splitDots = split "\\." (handlePlaceholders versionInfo.versionTemplate);
          splitVersion = genList (x: elemAt splitDots (x * 2)) (length splitDots / 2 + 1);

          # Picks the integers out from the start of each component.
          splitVersionInts = map getInt splitVersion;

          # The number of version components.
          numComponents = length splitVersionInts;

          # 0 or missing in the digits list means unlimited. Padded out to the correct size.
          digits' = genList (x: if x >= length digits then 0 else elemAt digits x) numComponents;

          # Returns true if the max digits are defined for each component of the version.
          canMakeVersionCode = length (filter (x: x > 0) digits') == length digits';

          # Reversed digits turned into factors for building the version code.
          # For instance, digits' of 1 2 3 4 becomes 1000 100 10 1.
          factors =
            if canMakeVersionCode then
              foldl' (s: x: s ++ [ (x * (elemAt s (length s - 1))) ]) [ 1 ] (
                genList (x: pow 10 (elemAt digits' (length digits' - x - 1))) (length digits' - 1)
              )
            else
              [ ];

          # Matches a version component and some possible other stuff after it.
          getComponentMatch =
            componentStr:
            assert isString componentStr && stringLength componentStr > 0;
            let
              match = builtins.match "^([0-9]+)(.*)$" componentStr;
            in
            match;

          # Replaces an integer at the start of the specified version component string.
          replaceInt =
            componentStr: x:
            let
              match = getComponentMatch componentStr;
            in
            if match == null then componentStr else toString x + (head (tail match));

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
                version = concatStringsSep "." (
                  genList (
                    x:
                    replaceInt (elemAt splitVersion x) (makeComponent (elemAt splitVersionInts x) (elemAt digits' x) 1)
                  ) elems
                );

                # And the version code.
                versionCode =
                  if canMakeVersionCode then
                    foldl' (s: x: s + x) 0 (
                      genList (
                        x:
                        (makeComponent (if x < elems then elemAt splitVersionInts x else 0)) (elemAt digits' x) (
                          elemAt factors (length factors - x - 1)
                        )
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
          # Make the full version and version code attributes accessible.
          inherit (nixFlakever 0) version versionCode;
        };

      # In case of typos.
      lib.mkFlakeVer = throw "You meant: lib.mkFlakever";

      # And, of course, flakever itself has a flakever.
      versionTemplate = "0.4.0-<lastModifiedDate>";

      inherit
        (self.lib.mkFlakever {
          inherit inputs;
          digits = [
            1
            1
            1
          ];
        })
        version
        versionCode
        ;
    };
}
