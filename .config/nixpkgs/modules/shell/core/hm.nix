{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.shell.core;
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

    config = mkMerge [
      (mkIf cfg.enable {
        programs.readline = {
          enable = true;
          extraConfig = ''
            set echo-control-characters off
          '';
        };

        programs.fzf = {
          enable = true;
          enableBashIntegration = true;
        };

        # programs.command-not-found = {
        #   enable = true;
        #   dbPath = ./programs.sqlite;
        # };

        home.sessionPath = [ "$HOME/.local/bin" ];

        home.packages = with pkgs; [
          gdu
          tree
        ];
      })
      (mkIf (cfg.enable && cfg.dev.enable) {
        home.packages = with pkgs; [ checkbashisms shellcheck ];
      })
      (mkIf (cfg.enable && cfg.queueing.enable) {
        services.pueue.enable = true;
      })
    ];
  }
