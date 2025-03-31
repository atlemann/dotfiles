{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.ext.networking.core;
  user = config.attributes.mainUser.name;
in
{
  options = {
    ext.networking.core = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable core networking customizations";
      };
      hostname = mkOption {
        type = types.str;
        default = config.attributes.machine.name;
        description = "Hostname";
      };
      hostId = mkOption {
        type = types.str;
        default = "";
        description = "Host ID";
      };
      # nameservers = mkOption {
      #   type = types.listOf types.str;
      #   default = [ "77.88.8.1" "77.88.8.8" "8.8.8.8" ];
      #   description = "DNS servers";
      # };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      networking = {
        hostName = cfg.hostname;
        firewall.enable = false;
        resolvconf = {
          enable = true;
          dnsExtensionMechanism = false;
        };
        networkmanager = {
          enable = true;
          unmanaged = [ "lo" ];
        };
        inherit (cfg) hostId; #nameservers;
      };
      users.users."${user}".extraGroups = [ "networkmanager" ];
    })
  ];
}
