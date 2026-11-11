{ config, lib, ... }:
with lib;

let
  cfg = config.shell.tmux;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      shell.tmux = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable tmux terminal multiplexer";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}".shell.tmux.enable = true;
    };
  }
