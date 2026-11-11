{ config, lib, ... }:
with lib;

let
  cfg = config.dev.python;
  user = config.attributes.mainUser.name;
  hm = config.home-manager.users."${user}";
in
  {
    options = {
      dev.python = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install Python development tools";
        };
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = hm.dev.python.packages;

      home-manager.users."${user}".dev.python.enable = true;
    };
  }
