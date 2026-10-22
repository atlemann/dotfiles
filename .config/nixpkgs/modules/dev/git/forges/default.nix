{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.git.forges;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      dev.git.forges = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Git forge CLIs (GitHub, GitLab).";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        dev.git.enable = mkDefault true;

        home-manager.users."${user}" = {
          home.packages = [ pkgs.glab ];

          programs.gh = {
            enable = true;
            settings = {
              git_protocol = "ssh";
            };
            extensions = [ pkgs.gh-dash ];
          };
        };
      })
    ];
  }
