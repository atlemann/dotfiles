{ config, lib, pkgs, ... }:

let
  sources = import ../../npins/default.nix;
  unstable = import sources.unstable { config.allowUnfree = true; };
in
{
  imports =
    [ ./hardware-configuration.nix
      (import ../../common.nix { inherit config lib pkgs sources unstable; })
      (import ../../packages.nix { inherit pkgs unstable; })
      "${sources.home-manager}/nixos/default.nix"
      ../../home-common.nix
    ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = "/boot";
    };
    supportedFilesystems = [ "zfs" ];
  };

  networking.hostName = "elisha";
  networking.hostId = "171f21ca";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.atle = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    packages = with pkgs; [];
  };

  system.stateVersion = "24.05"; # Did you read the comment?
}
