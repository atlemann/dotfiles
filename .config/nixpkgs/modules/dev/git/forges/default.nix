{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.git.forges;
  user = config.attributes.mainUser.name;

  # glab queries the Secret Service over D-Bus at startup, even when the token is
  # stored in its config file. With a locked keyring, and no one to answer the unlock
  # prompt (e.g. over SSH), it hangs. An unreachable bus makes it skip the keyring.
  glab = pkgs.symlinkJoin {
    name = "glab-${pkgs.glab.version}";
    paths = [ pkgs.glab ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/glab --set DBUS_SESSION_BUS_ADDRESS unix:path=/nonexistent
    '';
  };

  # Gerrit-like dashboard of the GitLab merge request stacks you push or review.
  mr-dash = pkgs.writers.writePython3Bin "mr-dash" {
    flakeIgnore = [ "E501" "W503" ];
    makeWrapperArgs = [
      "--prefix" "PATH" ":" (makeBinPath [ glab pkgs.delta pkgs.fzf pkgs.xdg-utils ])
      # Highlight diffs in the stylix colours, like bat.
      "--set-default" "BAT_THEME" "base16-stylix"
    ];
  } (builtins.readFile ./mr-dash.py);
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
          home.packages = [ glab mr-dash ];

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
