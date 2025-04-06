{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.browsers;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      browsers = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install browsers.";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        home-manager.users."${user}" = {
          home.packages = with pkgs; [
            vivaldi
            chromium
          ];
        };
      })
    ];
  }
