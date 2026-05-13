{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.claudecode;
in
  {
    options = {
      dev.claudecode = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install Claude Code along with its sandbox dependencies (bubblewrap, socat).";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          claude-code   # Anthropic's official CLI for Claude
          bubblewrap    # Required for Claude Code's sandbox feature (bwrap)
          socat         # Required for Claude Code's sandboxed network proxy
        ];
      })
    ];
  }
