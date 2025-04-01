{ config, lib, pkgs, ... }:
with pkgs.unstable.commonutils;
with lib;

let
  cfg = config.ext.networking.wireless;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      ext.networking.wireless = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable networking wireless support";
        };
        backend = mkOption {
          type = types.enum [ "iwd" "wpa_supplicant" ];
          default = "iwd";
          description = "Which system module to use";
        };
        wireless.driver = mkOption {
          type = types.str;
          default = "nl80211";
          description = "Driver name for `wireless` system module";
        };
        bluetooth.enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Bluetooth support";
        };
        tools.enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable network monitoring/debug tools";
        };
        wm.enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable WM tools/keybindings";
        };
      };
    };

    config = mkMerge [
      (mkIf (cfg.enable && cfg.backend == "iwd") {
        networking.wireless.iwd.enable = true;
        networking.networkmanager.wifi.backend = "iwd";
      })
      (mkIf (cfg.enable && cfg.backend == "wireless") {
        networking.wireless = {
          enable = true;
          inherit (cfg.wireless) driver;
          userControlled.enable = true;
        };
      })
      (mkIf (cfg.enable && cfg.bluetooth.enable) {
        hardware = {
          bluetooth = {
            enable = true;
            powerOnBoot = true;
            package = pkgs.bluez;
            settings = {
              General = {
                Enable = "Source,Sink,Media,Socket";
                Experimental = false;
              };
            };
          };
        };
        services.blueman.enable = true;
        home-manager.users."${user}" = { home.packages = with pkgs; [ bluetooth_battery ]; };
      })
      (mkIf (cfg.enable && cfg.tools.enable) { programs.wavemon.enable = true; })
      (mkIf (cfg.enable && cfg.wm.enable) { programs.nm-applet.enable = true; })
    ];
  }
