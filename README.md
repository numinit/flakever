# flakever

Use your flake's last-modified timestamp to create a version that's
suitable for nightly builds of enterprise software, while maintaining
the laziness that makes Nix great and keeping your inputs the same.

The Nix code only uses builtins, and takes an optional pkgs argument if you'd like to build the command line tool and use it in your builds. There are no external dependencies.

See examples/simple for an example.

More docs coming soon.
