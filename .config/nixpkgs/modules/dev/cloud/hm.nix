{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.cloud;
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

    config = mkIf cfg.enable {
      home.packages = with pkgs; [
        azure-cli
        awscli2
        buildkite-cli
        kubectl
        kubelogin
      ];
    };
  }
