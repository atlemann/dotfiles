{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.flameshot;
  user = config.attributes.mainUser.name;
  inherit (config.wmCommon) prefix;
in
  {
    options = {
      workstation.flameshot = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable flameshot screen shotter";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}" = {
        services.flameshot = {
          enable = true;
          settings = {
            General = {
              startupLaunch = true;
              showDesktopNotification = true;
              disabledTrayIcon = false;
              showStartupLaunchMessage = false;
            };
          };
        };
      };
    };
  }
