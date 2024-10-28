{ config, lib, pkgs, ... }:

let
  sources = import ../../npins/default.nix;
  unstable = import sources.unstable { config.allowUnfree = true; };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      (import ../../common.nix { inherit config lib pkgs sources unstable; })
      (import ../../packages.nix { inherit pkgs unstable; })
      (import ../../desktop.nix { inherit pkgs unstable; })
      "${sources.home-manager}/nixos/default.nix"
      ./home.nix
    ];

  # Bootloader
  boot = {
    loader = {
      grub = {
        enable = true;
        device = "/dev/sda";
        useOSProber = true;
      };
    };
  };

  # Set hostname
  networking = {
    hostName = "aru-ws"; # Define your hostname.
  };

  # Enable password auth
  services.openssh = {
    settings = {
      PasswordAuthentication = true;
    };
  };

  networking.firewall = {
    enable = false;
    allowedTCPPorts = [ 22 5000 ];
  };

  fileSystems."/mnt/internal" = {
    device = "jackson.resoptima.local:/mnt/bigstorage/internal";
    fsType = "nfs";
    options = ["x-systemd.automount" "noauto"];
  };

  fileSystems."/mnt/external" = {
    device = "jackson.resoptima.local:/mnt/bigstorage/external";
    fsType = "nfs";
    options = ["x-systemd.automount" "noauto"];
  };

  fileSystems."/mnt/data" = {
    device = "jackson.resoptima.local:/mnt/bigstorage/data";
    fsType = "nfs";
    options = ["x-systemd.automount" "noauto"];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
