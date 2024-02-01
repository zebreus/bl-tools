# bl808-nix-tools

Run various tools for flashing and developing the BL808 with Nix.

## Usage

Enter a shell with all the tools in `PATH`:

```sh
nix develop github:zebreus/bl808-nix-tools
```

You can also run individual commands like this:

```sh
# Run the devcube tool
nix run github:zebreus/bl808-nix-tools#devcube

# Run bouffalo-loader
nix run github:zebreus/bl808-nix-tools#bouffalo-loader

# Run bflb-mcu-tool
nix run github:zebreus/bl808-nix-tools#bflb-mcu-tool

# Run bflb-iot-tool
nix run github:zebreus/bl808-nix-tools#bflb-iot-tool

# Run print_boot_header from bl808-utils
nix run github:zebreus/bl808-nix-tools#print_boot_header

# Run gen_boot_header from bl808-utils
nix run github:zebreus/bl808-nix-tools#gen_boot_header

# Run BLFlashCommand
nix run github:zebreus/bl808-nix-tools#BLFlashCommand

# Run bflb_fw_post_proc
nix run github:zebreus/bl808-nix-tools#bflb_fw_post_proc
```

## About

I wrote this flake to be able to work with the BL808 on Nixos, but it should also work on any other Linux system that supports Nix.

The packaging is, for the most part, really hacky because I just wanted to get them to work, and the flashing utilities are only available as precompiled binaries or Python packages that modify their own environment.
