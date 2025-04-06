{ config, inputs, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.direnv;
  user = config.attributes.mainUser.name;
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

    config = mkMerge [
      (mkIf cfg.enable {
        home-manager.users."${user}" = {
          programs.direnv = {
            enable = true;
            nix-direnv.enable = true;
            enableBashIntegration = true;
          };
        };
      })
    ];
  }
