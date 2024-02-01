{
  description = "A lot of utilities for working with the BL808 SoC";

  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs?ref=refs/heads/master";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, fenix }:
    flake-utils.lib.eachDefaultSystem (system:
      with nixpkgs.legacyPackages.${system};
      rec {
        name = "bl808-tools";
        devShells.default = mkShellNoCC
          {
            ncurses = ncurses;
            buildInputs = [
              gnat13 # gcc with ada
              ncurses # make menuconfig
              m4
              flex
              bison # Generate flashmap descriptor parser
              go
              dtc
              nss
              bc

              # We need scan-build and ccc-analyzer, but only the version from clang-analyzer seems to work
              # https://github.com/NixOS/nixpkgs/issues/151367

              clang-analyzer
              clang-tools_16
              libxcrypt # For compiling clang before version 17
              ccache

              nil
              zlib
              openssl
              #acpica-tools # iasl
              pkg-config
              qemu # test the image
              gdb
              python3

              (fenix.packages.${system}.complete.withComponents [
                "cargo"
                "clippy"
                "rust-src"
                "rustc"
                "rustfmt"
              ])
              fenix.packages.${system}.rust-analyzer
            ];
            shellHook = ''
              # TODO remove?
              NIX_LDFLAGS="$NIX_LDFLAGS -lncurses"
            '';
          };

      }
    );
}
