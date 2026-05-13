{ config, inputs, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.git.core;
  user = config.attributes.mainUser.name;
  hm = config.home-manager.users."${user}";
  inherit (hm.xdg) dataHome;
in
  {
    options = {
      dev.git.core = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Git VCS infrastructure.";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        home-manager.users."${user}" = {
          programs = {
            gh = {
              enable = true;
              settings = {
                git_protocol = "ssh";
              };
              extensions = [ pkgs.gh-dash ];
            };
            git = {
              enable = true;
              userName = config.attributes.mainUser.fullName;
              userEmail = config.attributes.mainUser.email;
              aliases = {
                co = "checkout";
                cob = "checkout -b";
                ci = "commit";
                st = "status";
                br = "branch";
                bra = "branch -a";
                hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";
                ec = "config --global -e";
              };
              extraConfig = {
                merge = {
                  tool = "kdiff3";
                };
                mergetool = {
                  kdiff3 = {
                    trustExitCode = false;
                  };
                };
                diff = {
                  guitool = "kdiff3";
                };
                difftool = {
                  kdiff3 = {
                    trustExitCode = false;
                  };
                };
              };
            };
          };
        };

        shell.prompts.starship.modulesConfiguration = {
          git_branch = { only_attached = true; };
          git_commit = {
            commit_hash_length = 10;
            tag_disabled = false;
            tag_symbol = "🔖 ";
          };
          git_status = {
            diverged = "⇕⇡$ahead_count⇣$behind_count";
            conflicted = "✗ ($count) ";
            ahead = "⇡ ($count) ";
            behind = "⇣ ($count) ";
            untracked = "♾ ‍($count) ";
            stashed = "☂ ($count) ";
            modified = "♨ ($count) ";
            staged = "[++($count)](green) ";
            renamed = "⥂ ($count) ";
            deleted = "♺ ($count) ";
            style = "bold green";
          };
        };
      })
    ];
  }
