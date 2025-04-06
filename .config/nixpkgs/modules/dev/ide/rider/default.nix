{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.ide.rider;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      dev.ide.rider = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install Jet-brains Rider";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        home-manager.users."${user}" = {
          home.packages = with pkgs; [
            # realpath `which copilot-agent` and symlink in ~/.local/share/JetBrains/Rider2023.1/github-copilot-intellij/copilot-agent/bin
            github-copilot-intellij-agent
            jetbrains.rider
          ];
        };
      })
    ];
  }
