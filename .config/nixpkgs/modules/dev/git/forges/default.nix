{ config, lib, ... }:
with lib;

let
  cfg = config.dev.git.forges;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      dev.git.forges = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Git forge CLIs (GitHub, GitLab).";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}".dev.git.forges.enable = true;
    };
  }
