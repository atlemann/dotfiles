{ config, lib, ... }:
with lib;

let
  cfg = config.shell.vt.alacritty;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      shell.vt.alacritty = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Alacritty.";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}".shell.vt.alacritty.enable = true;
    };
  }
