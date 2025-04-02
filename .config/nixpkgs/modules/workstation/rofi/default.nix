{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.rofi;
  user = config.attributes.mainUser.name;
  inherit (config.wmCommon) prefix;
in
  {
    options = {
      workstation.rofi = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable rofi launcher";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}" = {
        programs.rofi = {
          enable = true;
          theme = "gruvbox-dark"; # TODO: Put in common place
          extraConfig = {
            modi = "combi";
            show-icons = true;
            hide-scrollbar = true;
          };
        };
      };
    };
  }
