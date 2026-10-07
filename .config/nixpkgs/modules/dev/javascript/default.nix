{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.javascript;
in
  {
    options = {
      dev.javascript = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install JavaScript/Node.js development tools";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          nodejs
          yarn
          gcc       # node-gyp needs a C/C++ compiler for native addons
        ];
      })
    ];
  }
