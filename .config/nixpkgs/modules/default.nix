{ config, inputs, lib, modulesPath, options, specialArgs }: {
  imports = [
    ./attributes.nix
    ./user.nix

    ./appearance/stylix
    ./networking/core
    ./networking/ssh
    ./networking/tailscale
    ./networking/wireless
    ./nix/core
    ./shell/alacritty
    ./shell/core
    ./shell/starship
    ./shell/tools
    ./workstation/sound
  ];
}
