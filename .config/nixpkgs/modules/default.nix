{ config, inputs, lib, modulesPath, options, specialArgs }: {
  imports = [
    ./attributes.nix
    ./user.nix
    ./home-manager.nix

    ./appearance/stylix
    ./browsers
    ./dev/cloud
    ./dev/direnv
    ./dev/dotnet
    ./dev/git/core
    ./dev/ide/rider
    ./dev/ide/vscode
    ./emacs
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
    ./workstation/video/opengl
    ./wm/i3
  ];
}
