{
  description = "A lot of utilities for working with the BL808 SoC";

  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs?ref=refs/heads/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, fenix }:
    flake-utils.lib.eachDefaultSystem
      (system:
        with nixpkgs.legacyPackages.${system};
        rec {
          name = "bl808-tools";


          packages.devcube =
            let
              devcubeSrc = stdenv.mkDerivation
                rec {
                  pname = "devcubeSrc";
                  version = "1.8.3";
                  src = fetchzip {
                    url = "https://openbouffalo.org/static-assets/bldevcube/BouffaloLabDevCube-v${version}.zip";
                    hash = "sha256-rMGe8yqbI6mfM5kopwmsunSaC+LEj2wO4uLUNL42tT4=";
                    stripRoot = false;
                  };

                  sourceRoot = ".";

                  installPhase = ''
                    runHook preInstall
                    mkdir -p $out/devcube
                    cp -r $src/utils $src/docs $src/chips $out/devcube
                    install -m755 -D $src/BLDevCube-ubuntu $out/devcube/BLDevCube-ubuntu
                    runHook postInstall
                  '';
                };

              devcubeContainer = dockerTools.buildImage {
                name = "devcube-container";
                fromImage = pkgs.dockerTools.pullImage {
                  imageName = "gameonwhales/xorg";
                  imageDigest = "sha256:61084c6435fefa19e8114d158f5d8663cf5fbc2c66d4db7d286999d2d94300d6";
                  sha256 = "sha256-LFybsh8Ni0Xah0A8HxYLRUtuEOqbsMljKeKgUxsAppI=";
                  finalImageName = "devcube-container";
                  finalImageTag = "latest";
                  os = "linux";
                  arch = "x86_64";
                };

                copyToRoot = pkgs.buildEnv {
                  name = "devcube-root";
                  paths = [ devcubeSrc ];
                  pathsToLink = [ "/devcube" ];
                };

                runAsRoot = ''
                  #!${stdenv.shell}
                  export PATH=/bin:/usr/bin:/sbin:/usr/sbin:$PATH
                  ${dockerTools.shadowSetup}
                  # apt update && apt install -y xterm
                  # groupadd -r redis
                  # useradd -r -g redis -d /data -M redis
                  # mkdir /data
                  # chown redis:redis /data

                  mkdir -p /root/.config
                  cat  << EOF > /root/.config/QtProject.conf
                  [FileDialog]
                  history=@Invalid()
                  lastVisited=file:///workdir
                  qtVersion=5.15.2
                  shortcuts=file:, file:///workdir
                  sidebarWidth=170
                  treeViewHeader=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x2\x36\0\0\0\x4\x1\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\x4\0\0\x1\x31\0\0\0\x1\0\0\0\0\0\0\0\x44\0\0\0\x1\0\0\0\0\0\0\0I\0\0\0\x1\0\0\0\0\0\0\0x\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\xff\xff\xff\xff)
                  viewMode=Detail
                  EOF

                '';

                config = {
                  Cmd = [ "/devcube/BLDevCube-ubuntu" ];
                  WorkingDir = "/devcube";
                };
              };
            in
            writeTextFile rec {
              name = "devcube-1.8.3";
              executable = true;
              destination = "/bin/devcube";
              text = ''
                #!${stdenv.shell}
      
                ${xorg.xhost}/bin/xhost +local:root
              
                ${podman}/bin/podman run --rm -it --privileged --net host -e DISPLAY=$DISPLAY -v $(pwd):/workdir docker-archive:${devcubeContainer}
              '';
            };



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
