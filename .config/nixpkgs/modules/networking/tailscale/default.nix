{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.ext.networking.tailscale;
in
  {
    options = {
      ext.networking.tailscale = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Tailscale VPN";
        };
      };
    };

    config = mkIf cfg.enable {
      services.tailscale = {
        enable = true;
      };
    };
  }
