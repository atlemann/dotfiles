{ config, lib, ... }:
with lib;

let
  cfg = config.shell.core;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      shell.core = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable core shell setup";
        };
        queueing.enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable shell commands queueing, using `pueue` machinery";
        };
        dev.enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable shell-related development infra";
        };
      };
    };

    config = mkIf cfg.enable {
      console.useXkbConfig = true;

      home-manager.users."${user}".shell.core = {
        enable = true;
        inherit (cfg) queueing dev;
      };
    };
  }
