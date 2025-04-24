{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.zathura;
  user = config.attributes.mainUser.name;
  inherit (config.wmCommon) prefix;
in
  {
    options = {
      workstation.zathura = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable zathura PDF viewer";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}" = {
        programs.zathura = {
          enable = true;
        };
      };
    };
  }
