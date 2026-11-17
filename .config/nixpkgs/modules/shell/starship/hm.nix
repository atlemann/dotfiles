{ config, lib, ... }:
with lib;

let
  cfg = config.shell.prompts.starship;
in
  {
    options = {
      shell.prompts.starship = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable starship";
        };
        modulesConfiguration = mkOption {
          type = types.attrs;
          default = { };
          description = "Starship additional modules configuration";
        };
        configuration = mkOption {
          type = types.attrs;
          default = {
            add_newline = false;
            scan_timeout = 50;
            command_timeout = 2000;
            character = {
              success_symbol = "[➜](bold green) ";
              error_symbol = "[➜](bold red) ";
            };
            cmd_duration = {
              min_time = 100;
              format = "[$duration](bold yellow)";
              show_notifications = false;
            };
            directory = {
              truncation_length = 8;
            };
            line_break = {
              disabled = true;
            };
            nix_shell.disabled = true;
          } // optionalAttrs (cfg.modulesConfiguration != { }) cfg.modulesConfiguration;
          description = "Starship prompt configuration";
          visible = false;
          internal = true;
          readOnly = true;
        };
      };
    };

    config = mkIf cfg.enable {
      programs.starship = {
        enable = true;
        enableBashIntegration = true;
        settings = cfg.configuration;
      };
    };
  }
