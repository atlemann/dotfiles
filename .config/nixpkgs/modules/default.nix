{ config, inputs, lib, modulesPath, options, specialArgs }: {
  imports = [
    ./attributes.nix
    ./user.nix

    ./appearance/stylix
    ./networking/core
    ./networking/ssh
    ./networking/tailscale
    ./nix/core
  ];
}
