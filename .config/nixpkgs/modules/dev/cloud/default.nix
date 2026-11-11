{ config, lib, ... }:
with lib;

let
  cfg = config.dev.cloud;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      dev.cloud = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install cloud dev tools";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}".dev.cloud.enable = true;
    };
  }
