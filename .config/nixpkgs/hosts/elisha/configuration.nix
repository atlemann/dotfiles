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

  services = {
    samba = {
      enable = true;
      securityType = "user";
      openFirewall = true;
      extraConfig =
      ''
        workgroup = WORKGROUP
          security = user
          server string = elisha
          netbios name = elisha
          hosts allow = 192.168.1. 127.0.0.1 localhost
          hosts deny = 0.0.0.0/0
          guest account = nobody
          map to guest = bad user
      '';
      shares = {
        bilder = {
          path = "/zfspool/data/bilder";
          "read only" = false;
          "browseable" = "yes";
          "writable" = "yes";
          "guest ok" = "yes";
          "create mask" = "0644";
          "directory mask" = "0755";
          "valid users" = "aru, atle";
          "force user" = "aru";
        };
      };
    };

    samba-wsdd = {
      enable = true;
      openFirewall = true;
      hostname = "elisha";
    };
  };

  networking.firewall = {
    enable = true;
    allowPing = true;
  };

  system.stateVersion = "24.05"; # Did you read the comment?
}
