{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.ide.cursor;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      dev.ide.cursor = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install Cursor AI editor";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        home-manager.users."${user}" = {
          home.packages = with pkgs; [ code-cursor ];
        };
      })
    ];
  }
