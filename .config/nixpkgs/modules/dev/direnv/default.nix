{ config, lib, ... }:
with lib;

let
  cfg = config.dev.direnv;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      dev.direnv = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable direnv.";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}".dev.direnv.enable = true;
    };
  }
