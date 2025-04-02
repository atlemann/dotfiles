{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.ext.virtualization.core;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      ext.virtualization.core = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Libvirt";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          libvirt
        ];

        virtualisation = {
          libvirtd.enable = true;
          kvmgt.enable = true;
          spiceUSBRedirection.enable = true;
        };

        users.users."${user}".extraGroups = [ "libvirtd" ];
      })
    ];
  }
