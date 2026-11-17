{ config, lib, ... }:
with lib;

let
  cfg = config.dev.git;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      dev.git = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Git VCS infrastructure.";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}".dev.git.enable = true;
    };
  }
