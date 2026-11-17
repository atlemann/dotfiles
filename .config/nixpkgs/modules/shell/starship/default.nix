{ config, lib, ... }:
with lib;

let
  cfg = config.shell.prompts.starship;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      shell.prompts.starship = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable starship";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}".shell.prompts.starship.enable = true;
    };
  }
