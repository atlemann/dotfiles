{ config, lib, pkgs, ... }:

let
  sources = import ./npins/default.nix;
  unstable = import sources.unstable { config.allowUnfree = true; };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      (import ./common.nix { inherit config lib pkgs sources unstable; })
      (import ./packages.nix { inherit pkgs unstable; })
      (import ./desktop.nix { inherit pkgs unstable; })
      "${sources.home-manager}/nixos/default.nix"
      ./home.nix
    ];

  nix = {
    settings = {
      trusted-users = [ "aru" ];
    };
  };

  # Bootloader
  boot = {
    loader = {
      grub = {
        enable = true;
        device = "/dev/sda";
        useOSProber = true;
      };

#      tmp.cleanOnBoot = true;
    };
  };

  # Enable networking
  networking = {
    hostName = "aru-ws"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  };

  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.aru = {
    isNormalUser = true;
    description = "Atle Rudshaug";
    extraGroups = [
      "wheel"
      "networkmanager"
      "libvirtd"
      "docker"
    ];
    packages = with pkgs; [];
  };

  # List services that you want to enable:

  # Security
  #security.pam.services.gdm.enableGnomeKeyring = true;
  #services.gnome.gnome-keyring.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
