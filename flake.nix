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


          # The fastest way I got this to run was to use a docker container with X11 forwarding
          packages.BLDevCube =
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
            writeTextFile {
              name = "BLDevCube-1.8.3";
              executable = true;
              destination = "/bin/BLDevCube";
              text = ''
                #!${stdenv.shell}

                ${xorg.xhost}/bin/xhost +local:root

                ${podman}/bin/podman run --rm -it --privileged --net host -e DISPLAY=$DISPLAY -v $(pwd):/workdir docker-archive:${devcubeContainer}
              '';
            };

          # This is just a python script that has two dependencies.
          # If you are targeting the BL808 I will automatically add the `-C bl808_header_cfg.conf` flag with the correct path to bl808_header_cfg.conf
          packages.bouffalo-loader =
            let
              python = (python3.withPackages (python-pkgs: [
                python-pkgs.pyserial
                python-pkgs.pyelftools
              ]));
            in
            stdenv.mkDerivation
              rec {
                pname = "bouffalo-loader";
                version = "unstable";
                src = fetchFromGitHub {
                  owner = "smaeul";
                  repo = pname;
                  rev = "7275ba2744a53efbfb29a199965f04cd4459b60d";
                  sha256 = "sha256-CwS2wLoL3ETRypwewB+z8bXZCRTH22EHIpOd45tG+bY=";
                };

                buildPhase = "true";

                installPhase = ''
                  runHook preInstall
                  mkdir -p $out/bin
                  mkdir -p $out/share/bouffalo-loader

                  cp -r $src/* $out/share/bouffalo-loader

                  cat << EOF > $out/bin/bouffalo-loader
                  #!${stdenv.shell}


                  if [[ "\$*" == *"bl808"* ]]; then
                    if [[ "\$*" == *"-C"* ]]; then
                      true
                    else
                      ${python}/bin/python3 $out/share/bouffalo-loader/loader.py -C $out/share/bouffalo-loader/bl808_header_cfg.conf "\$@"
                      exit 0
                    fi
                  fi

                  ${python}/bin/python3 $out/share/bouffalo-loader/loader.py "\$@"


                  EOF
                  chmod +x $out/bin/bouffalo-loader

                  runHook postInstall
                '';
              };

          # Bouffalo-loader fork with extra features for oreboot 
          packages.bouffalo-loader-extended =
            let
              python = (python3.withPackages (python-pkgs: [
                python-pkgs.pyserial
                python-pkgs.pyelftools
              ]));
            in
            stdenv.mkDerivation
              rec {
                pname = "bouffalo-loader-extended";
                version = "unstable";
                src = fetchFromGitHub {
                  owner = "orangecms";
                  repo = "bouffalo-loader";
                  rev = "b4754308bd7423bbf42b44d0144dfbc1bcc1489c";
                  sha256 = "sha256-giPtrZnBc5SpndC4YDX5rwGJk3w2T0nu96iRn+Hltek=";
                };

                buildPhase = "true";

                installPhase = ''
                  runHook preInstall
                  mkdir -p $out/bin
                  mkdir -p $out/share/bouffalo-loader-extended

                  cp -r $src/* $out/share/bouffalo-loader-extended

                  # Patch out weird error that sometimes happens.
                  sed -i '405s/raise Exception/logger.info/' $out/share/bouffalo-loader-extended/loader.py

                  cat << EOF > $out/bin/bouffalo-loader-extended
                  #!${stdenv.shell}


                  if [[ "\$*" == *"bl808"* ]]; then
                    if [[ "\$*" == *"-C"* ]]; then
                      true
                    else
                      ${python}/bin/python3 $out/share/bouffalo-loader-extended/loader.py -C $out/share/bouffalo-loader-extended/bl808_header_cfg.conf "\$@"
                      exit 0
                    fi
                  fi

                  ${python}/bin/python3 $out/share/bouffalo-loader-extended/loader.py "\$@"


                  EOF
                  chmod +x $out/bin/bouffalo-loader-extended

                  runHook postInstall
                '';
              };

          packages.bflb-crypto-plus = python311Packages.buildPythonPackage rec {
            pname = "bflb_crypto_plus";
            version = "1.0";

            src = fetchPypi {
              inherit pname version;
              hash = "sha256-sbSDh05dLstJ+fhSWXFa2Ut2+WJ7Pen6Z39spc5mYkI=";
            };

            nativeBuildInputs = [
              python311Packages.setuptools
            ];

            propagatedBuildInputs = [
              python311Packages.setuptools
              python311Packages.pycryptodome
            ];
          };
          packages.pycklink = python311Packages.buildPythonPackage rec {
            pname = "pycklink";
            version = "0.1.1";

            src = fetchPypi {
              inherit pname version;
              hash = "sha256-Ub3a72V15Fkeyo7RkbjMaj6faUrcC8RkRRSbNUuq/ks=";
            };

            nativeBuildInputs = [
              python311Packages.setuptools
            ];

            propagatedBuildInputs = [
              python311Packages.setuptools
            ];
          };
          packages.python3WithBouffalo = (python3.withPackages (python-pkgs: [
            python311Packages.setuptools
            python311Packages.pyserial
            python311Packages.pyelftools
            python311Packages.pylink-square
            python311Packages.portalocker
            python311Packages.ecdsa
            python311Packages.pycryptodome
            packages.bflb-crypto-plus
            packages.pycklink
          ]));

          # Real fhs bubblewrap would be better but I couldn't get it to work quickly.
          # This is hacky but it works.
          packages.init-python-venv = stdenv.mkDerivation
            rec {
              pname = "init-python-venv";
              version = "unstable";
              src = ./.;

              buildPhase = "true";

              installPhase = ''
                runHook preInstall
                mkdir -p $out/bin

                cat << EOF > $out/bin/init-python-venv
                #!${stdenv.shell}

                mkdir -p ~/.bouffalolab-python-tools
                touch ~/.bouffalolab-python-tools/nix-store-path
                if [[ \$(cat ~/.bouffalolab-python-tools/nix-store-path) == "$out" ]]; then
                  exit 0
                fi
    
                rm -rf ~/.bouffalolab-python-tools
                mkdir -p ~/.bouffalolab-python-tools
                OLD_DIR=\$(pwd)
                cd ~/.bouffalolab-python-tools
                ${packages.python3WithBouffalo}/bin/python3 -m venv .venv
                source .venv/bin/activate
                pip install bflb_iot_tool
                pip install bflb_mcu_tool
                echo $out > ~/.bouffalolab-python-tools/nix-store-path
                EOF
                chmod +x $out/bin/init-python-venv

                runHook postInstall
              '';
            };
          packages.bflb-iot-tool = writeTextFile rec {
            name = "bflb-iot-tool";
            executable = true;
            destination = "/bin/bflb-iot-tool";
            text = ''
              #!${stdenv.shell}

              ${packages.init-python-venv}/bin/init-python-venv
              source ~/.bouffalolab-python-tools/.venv/bin/activate
              python3 -m bflb_iot_tool "$@"
            '';
          };
          packages.bflb-mcu-tool = writeTextFile rec {
            name = "bflb-mcu-tool";
            executable = true;
            destination = "/bin/bflb-mcu-tool";
            text = ''
              #!${stdenv.shell}

              ${packages.init-python-venv}/bin/init-python-venv
              source ~/.bouffalolab-python-tools/.venv/bin/activate
              python3 -m bflb_mcu_tool "$@"
            '';
          };

          # Finally a simple package
          # There is probably a way to get the two programs in the same package
          # Maybe with apps, idk
          packages.print_boot_header = stdenv.mkDerivation {
            name = "print_boot_header";
            version = "unstable";
            src = fetchFromGitHub {
              owner = "Pavlos1";
              repo = "bl808-utils";
              rev = "48363b7b76f596b36021b0ebe58ac53582b209f5";
              sha256 = "sha256-XAuxPByB2TaipxW9IS4X7Jphty4EguiDt7lgPs0RzQ4=";
            };
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp print_boot_header $out/bin/print_boot_header
              runHook postInstall
            '';
          };
          packages.gen_boot_header = stdenv.mkDerivation {
            name = "gen_boot_header";
            version = "unstable";
            src = fetchFromGitHub {
              owner = "Pavlos1";
              repo = "bl808-utils";
              rev = "48363b7b76f596b36021b0ebe58ac53582b209f5";
              sha256 = "sha256-XAuxPByB2TaipxW9IS4X7Jphty4EguiDt7lgPs0RzQ4=";
            };
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp gen_boot_header $out/bin/gen_boot_header
              runHook postInstall
            '';
          };

          # Same as the python venv but for the flash command
          # Also uses steam-run because why not
          packages.init-flashcommand-env = stdenv.mkDerivation
            rec {
              pname = "init-flashcommand-env";
              version = "unstable";
              src = fetchFromGitHub {
                owner = "bouffalolab";
                repo = "bouffalo_sdk";
                rev = "302e017ea06b4c75963212f7144f8800c05901f1";
                sha256 = "sha256-+OzUPI9lymqv+PuSnwIQD+ZPJUuxRzAw/q4YtyACnN0=";
              };

              buildPhase = "true";

              installPhase = ''
                runHook preInstall
                mkdir -p $out/flash
                mkdir -p $out/bin

                cp -r $src/tools/bflb_tools/bouffalo_flash_cube/{utils,chips,docs} $out/flash
                cp $src/tools/bflb_tools/bouffalo_flash_cube/BLFlashCommand-ubuntu $out/flash/BLFlashCommand
                cp $src/tools/bflb_tools/bflb_fw_post_proc/bflb_fw_post_proc-ubuntu $out/flash/bflb_fw_post_proc
                chmod +x $out/flash/BLFlashCommand
                chmod +x $out/flash/bflb_fw_post_proc

                cat << EOF > $out/bin/init-flashcommand-env
                #!${stdenv.shell}

                mkdir -p ~/.bouffalolab-binary-tools/flash
                touch ~/.bouffalolab-binary-tools/flash/nix-store-path
                if [[ \$(cat ~/.bouffalolab-binary-tools/flash/nix-store-path) == "$out" ]]; then
                  exit 0
                fi
                
                rm -rf ~/.bouffalolab-binary-tools/flash
                OLD_DIR=\$(pwd)
                cp -r $out/flash ~/.bouffalolab-binary-tools/flash
                chmod -R +rw ~/.bouffalolab-binary-tools/flash
                chmod +x ~/.bouffalolab-binary-tools/flash/BLFlashCommand
                chmod +x ~/.bouffalolab-binary-tools/flash/bflb_fw_post_proc
                
                echo $out > ~/.bouffalolab-binary-tools/flash/nix-store-path
                EOF
                chmod +x $out/bin/init-flashcommand-env

                runHook postInstall
              '';
            };

          packages.BLFlashCommand = writeTextFile rec {
            name = "BLFlashCommand";
            executable = true;
            destination = "/bin/BLFlashCommand";
            text = ''
              #!${stdenv.shell}

              ${packages.init-flashcommand-env}/bin/init-flashcommand-env
              ${steamPackages.steam-fhsenv-without-steam.run}/bin/steam-run ~/.bouffalolab-binary-tools/flash/BLFlashCommand "$@"
            '';
          };
          # I am not sure what this command does, but it was easy to package it alongside the BLFlashCommand
          # It probably doesn't even need steam-run
          # It also doesn't need to write in its directory
          # It seems broken but I tried it in a ubuntu container and it did behave the same way
          packages.bflb_fw_post_proc = writeTextFile rec {
            name = "bflb_fw_post_proc";
            executable = true;
            destination = "/bin/bflb_fw_post_proc";
            text = ''
              #!${stdenv.shell}

              ${packages.init-flashcommand-env}/bin/init-flashcommand-env
              ${steamPackages.steam-fhsenv-without-steam.run}/bin/steam-run ~/.bouffalolab-binary-tools/flash/bflb_fw_post_proc "$@"
            '';
          };

          packages.BLFlashCube =
            let
              BLFlashCubeSrc = stdenv.mkDerivation
                {
                  pname = "BLFlashCubeSrc";
                  version = "1.8.3";
                  src = fetchFromGitHub {
                    owner = "bouffalolab";
                    repo = "bouffalo_sdk";
                    rev = "302e017ea06b4c75963212f7144f8800c05901f1";
                    sha256 = "sha256-+OzUPI9lymqv+PuSnwIQD+ZPJUuxRzAw/q4YtyACnN0=";
                  };

                  sourceRoot = ".";

                  installPhase = ''
                    runHook preInstall
                    mkdir -p $out/flashcube
                    cp -r $src/tools/bflb_tools/bouffalo_flash_cube/{utils,docs,utils} $out/flashcube
                    install -m755 -D $src/tools/bflb_tools/bouffalo_flash_cube/BLFlashCube-ubuntu $out/flashcube/BLFlashCube-ubuntu
                    runHook postInstall
                  '';
                };

              flashcubeContainer = dockerTools.buildImage {
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
                  name = "flashcube-root";
                  paths = [ BLFlashCubeSrc ];
                  pathsToLink = [ "/flashcube" ];
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
                  Cmd = [ "/flashcube/BLFlashCube-ubuntu" ];
                  WorkingDir = "/flashcube";
                };
              };
            in
            writeTextFile {
              name = "BLFlashCube-1.0.8";
              executable = true;
              destination = "/bin/BLFlashCube";
              text = ''
                #!${stdenv.shell}

                ${xorg.xhost}/bin/xhost +local:root

                ${podman}/bin/podman run --rm -it --privileged --net host -e DISPLAY=$DISPLAY -v $(pwd):/workdir docker-archive:${flashcubeContainer}
              '';
            };

          devShells.default = mkShellNoCC
            {
              ncurses = ncurses;
              buildInputs = [
                packages.BLDevCube
                packages.bouffalo-loader
                packages.bouffalo-loader-extended
                packages.bflb-mcu-tool
                packages.bflb-iot-tool
                packages.print_boot_header
                packages.gen_boot_header
                packages.BLFlashCommand
                packages.BLFlashCube
                packages.bflb_fw_post_proc

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

                rustup
                minicom
              ];
              shellHook = ''
                # TODO remove?
                NIX_LDFLAGS="$NIX_LDFLAGS -lncurses"
              '';
            };

        }
      );
}
