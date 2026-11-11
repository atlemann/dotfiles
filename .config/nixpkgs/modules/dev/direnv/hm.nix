{ config, lib, ... }:
with lib;

let
  cfg = config.dev.direnv;
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
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        enableBashIntegration = true;
      };
    };
  }
