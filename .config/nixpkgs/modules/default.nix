{ config, inputs, lib, modulesPath, options, specialArgs }: {
  imports = [
    ./attributes.nix
    ./user.nix

    ./appearance/stylix
    ./dev/git/core
    ./networking/core
    ./networking/ssh
    ./networking/tailscale
    ./networking/wireless
    ./nix/core
    ./shell/alacritty
    ./shell/bash
    ./shell/core
    ./shell/starship
    ./shell/tools
    ./virt/core
    ./virt/docker
    ./workstation/drives
    ./workstation/dunst
    ./workstation/flameshot
    ./workstation/rofi
    ./workstation/sound
  ];
}
