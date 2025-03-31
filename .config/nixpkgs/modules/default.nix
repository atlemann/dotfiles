{ config, inputs, lib, modulesPath, options, specialArgs }: {
  imports = [
    ./attributes.nix
    ./user.nix

    ./appearance/stylix
    ./networking/core
    ./nix/core
  ];
}
