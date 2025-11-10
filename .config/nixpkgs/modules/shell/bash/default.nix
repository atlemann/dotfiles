{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.shell.bash;
  user = config.attributes.mainUser.name;
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

    config = mkMerge [
      (mkIf cfg.enable {
        home-manager.users."${user}" = {
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
      })
    ];
  }
