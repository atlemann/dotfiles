{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.cloud;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      dev.cloud = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install cloud dev tools";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        home-manager.users."${user}" = {
          home.packages = with pkgs; [
            azure-cli
            kubectl
            kubelogin
          ];
        };
      })
    ];
  }
