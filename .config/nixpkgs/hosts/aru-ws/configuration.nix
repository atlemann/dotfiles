{ config, lib, pkgs, ... }:

let
  sources = import ../../npins/default.nix;
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../common.nix
      ../../packages.nix
      ../../desktop.nix
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

  services.xserver = {
    displayManager = {
      setupCommands = ''
        LEFT='DP-1'
        RIGHT='DP-2'
        ${pkgs.xorg.xrandr}/bin/xrandr --output $LEFT --primary --auto --output $RIGHT --right-of $LEFT --rotate left
      '';
    };
  };

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = false;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
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
