{ config, inputs, lib, pkgs, ... }:
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

    config = mkMerge [
      (mkIf cfg.enable {
        console.useXkbConfig = true;

        home-manager.users."${user}" = {
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

          home.packages = with pkgs; [
            gdu
          ];
        };
      })
      (mkIf (cfg.enable && cfg.dev.enable) {
        home-manager.users."${user}" = { home.packages = with pkgs; [ checkbashisms shellcheck ]; };
      })
      (mkIf (cfg.enable && cfg.queueing.enable) {
        home-manager.users."${user}" = {
          home.packages = with pkgs; [ pueue ];
        };
        systemd.user.services."pueued" = {
          description = "Pueue daemon";
          path = [ pkgs.bash ];
          serviceConfig = {
            ExecStart = "${pkgs.pueue}/bin/pueued";
            ExecReload = "${pkgs.pueue}/bin/pueued";
            Restart = "no";
            StandardOutput = "journal+console";
            StandardError = "inherit";
          };
          wantedBy = [ "multi-user.target" ];
        };
      })
    ];
  }
