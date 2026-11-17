{ config, lib, ... }:
with lib;

let
  cfg = config.shell.tools;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      shell.tools = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Add extra shell tools";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}".shell.tools.enable = true;
    };
  }
