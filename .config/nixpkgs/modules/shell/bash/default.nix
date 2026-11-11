{ config, lib, ... }:
with lib;

let
  cfg = config.shell.bash;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      shell.bash = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Bash shell";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}".shell.bash.enable = true;
    };
  }
