{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.shell.bash;
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
      programs.bash = {
        enable = true;
        shellAliases = {
          cat = "${pkgs.bat}/bin/bat";
          catb = "${pkgs.bat}/bin/bat -A";

          j = "br -s";

          df = "${pkgs.duf}/bin/duf";
          du = "${pkgs.dust}/bin/dust";
        };
      };
    };
  }
