{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.dunst;
  user = config.attributes.mainUser.name;
  inherit (config.wmCommon) prefix;
in
  {
    options = {
      workstation.dunst = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable dunst notifications";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}" = {
        services.dunst = {
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
