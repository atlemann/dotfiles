{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.herdr;
in
  {
    options = {
      dev.herdr = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to install herdr, a terminal workspace manager for AI coding agents.

            Also enables dev.claudecode by default, since that is the agent herdr
            is mostly used with here. herdr itself is agent-agnostic, so set
            dev.claudecode.enable = false to opt out.
          '';
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        environment.systemPackages = [ pkgs.herdr ];

        dev.claudecode.enable = mkDefault true;
      })
    ];
  }
