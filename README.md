# flakever

What if Nix had something like Jenkins build numbers, but they were generated
entirely with flake inputs?

With flakever, you can automatically generate versions from a template.
flakever uses metadata from flake inputs to automatically compute both a
version and a version code, including a nightly build number that changes as
the repository is modified by your team.

## Usecases

See [examples/simple](https://github.com/numinit/flakever/tree/master/examples/simple)
and [examples/multibranch](https://github.com/numinit/flakever/tree/master/examples/multibranch).

There are two main usecases: projects where either simple or last modified
date-based versions are okay, and multibranch projects where branches are
either versioned independently or need a nightly build number.

### Single repository

Set `outputs.versionTemplate` to your version template. See
[Version Templates](#version-templates) for more details. Note that the
`<nightly>` placeholder will always be set to 0 in this case.

### Multibranch versions and nightly builds

Since nightly build numbers are based on the difference between last-modified
timestamps of your repo and a special flake that just exposes a version
template, you will need a separate repo that _just_ contains a
[version template](#version-templates) if you'd like to use it that way.

Nightly builds are mostly useful in larger projects, so you don't have to set
it up this way if you don't want to. However, if you'd like to manage your
project's version with a dedicated repository (which may also be useful in
larger projects), you may want to consider this approach.

An example repository is [numinit/flakever-example-version](https://github.com/numinit/flakever-example-version/).
Note that `examples/multibranch` includes multiple of its branches as flake
inputs, which are automatically picked up by flakever.

**NOTE:** To reset your nightly build number for a branch (e.g. flakever-dev),
modify the version repo and run: `nix flake lock --update-input flakever-dev`.
This is similar to clearing or manually advancing the build number in Jenkins.

## Version templates

A **version template** is a string that contains everything flakever needs to
version your software. It consists of a standard dot-separated version with
as many or few **numerically prefixed** components as you like, and
placeholders.

For instance: `1.2.3` or `1.2.3-<lastModifiedDate>`, or
`1.2.3.<lastModifiedDate>-<branch>` would all be valid version templates.

Here are all of the placeholders:

|Placeholder|Example|Description|
|:----------|:------|:----------|
|`<branch>`|version|Passed through `branch` argument to lib.mkFlakever.|
|`<longRev>`|242c98f67a3f2d2287346a77477438c1d3e4943b|Long git revision of the
current flake.|
|`<rev>`|242c89f-dirty|Short git revision of the current flake.|
|`<lastModifiedDate>`|20250628|Last-modified date of your flake, in YYYYMMDD
format.|
|`<lastModifiedTime>`|123456|Last modified time of your flake, in HHMMSS
format.|
|`<nightly>`|42|This is the most powerful template placeholder: it's the number
of days between lastModified of the input containing your version and the latest
lastModified in your flake inputs, with a minimum of 1, and a rate of increase
configurable with `secondsPerNightly`. This allows you to increase the version
built into your software at a regular interval for nightly builds, but only if
any of the inputs changed, self included. This also lets you reset the nightly
build counter with a `nix flake update`.|

## Version codes

flakever can automatically generate a **version code** from your version string,
while simultaneously saturating increasing version components at a given number
of digits. You do this by specifying the `digits` option in your flakever
config.

**NOTE:** Version codes corresponding to version strings are useful in some
build pipelines, like Android.

For example, `digits = [ 1 2 2 3 ]` would allow versions that look like
`0.0.0.0` up to `9.99.99.999`, and generate a version code that ranges from 0
to 99999999. Parts can be arbitrarily suffixed and still parse so long as they
start with a sequence of digits; for instance, a version template of
`1.2.3.4-foo` would parse as `10203004`.

As another example, a template of `1.2.<nightly>-foo` with
`digits = [ 1 2 2 ]` without a change to `secondsPerNightly` would saturate
at `1.2.99-foo` and `10299`. Flakever does this by replacing leading sequences
of digits in the version using Nix prior to building the Bash utility that
outputs the version.
