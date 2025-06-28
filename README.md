# flakever

Use your flake's last-modified timestamp to create a version that's suitable
for nightly builds of enterprise software, while maintaining the laziness that
makes Nix great and keeping your inputs the same.

The Nix code only uses builtins, and takes an optional pkgs argument if you'd
like to build a command line tool to version your builds. There are no
external dependencies. The Nix version gives you the same functionality with no
impurities. This lets you generate date or time-based version codes in your
builds, while avoiding rebuilds due to changing inputs.

## Examples

See examples/simple and examples/multibranch.

**NOTE:** To reset your nightly build number for a branch (e.g. flakever-dev),
modify the version repo and run: `nix flake lock --update-input flakever-dev`

## Version templates

A **version template** is a string that contains everything flakever needs to
version your software. It consists of a standard dot-separated version with
as many or few **numerically prefixed** components as you like, and placeholders.

For instance: `1.2.3` or `1.2.3-<date>`, or `1.2.3.<date>-<branch>` would all
be valid version templates. Here are all of the placeholders:

|Placeholder|Example|Description|
|:----------|:------|:----------|
|`<branch>`|version|Passed through `branch` argument to lib.mkFlakever.|
|`<longRev>`|242c98f67a3f2d2287346a77477438c1d3e4943b|Long git revision of the current flake.|
|`<rev>`|242c89f-dirty|Short git revision of the current flake.|
|`<lastModifiedDate>`|20250628|Last-modified date of your flake, in YYYYMMDD format.|
|`<lastModifiedTime>`|123456|Last modified time of your flake, in HHMMSS format.|
|`<date>`|20250101|The current date. In pure mode, this is always 20250101, and is configurable with `defaultDate` and `dateFormat`.|
|`<nightly>`|42|This is the most powerful template placeholder: it's the number of days between lastModifiedDate of the input containing your version and now, with a minimum of 1, and a rate of increase configurable with `secondsPerNightly`. In pure mode, this is always 0. This allows you to increase the version built into your software at a regular interval for nightly builds without causing a rebuild by changing the version in your derivation. This also lets you reset the nightly build counter with a `nix flake update`.|

## Version codes

flakever can automatically generate a **version code** from your version string,
while simultaneously saturating increasing version components at a given number
of digits. You do this by specifying the `digits` option in your flakever
config.

**NOTE:** Version codes corresponding to version strings are useful in some
build pipelines, like Android.

For example, `digits = [ 1 2 2 3 ]` would allow versions that look like
`0.0.0.0` up to `9.99.99.999`, and generate a version code that ranges from 0
to 99999999. Parts can be arbitrarily suffixed and still parse so long as they;
start with a sequence of digits; for instance, a version template of
`1.2.3.4-foo` would parse as `10203004`. As another example, a template of
`1.2.<nightly>-foo` with `digits = [ 1 2 2 ]` without a change to
`secondsPerNightly` would saturate at `1.2.99-foo` and `10299`. Flakever
does this by replacing leading sequences of digits in the version using Nix
prior to building the Bash utility that outputs the version.

