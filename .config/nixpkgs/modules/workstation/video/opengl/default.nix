{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.video.opengl;
in
  {
    options = {
      workstation.video.opengl = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable OpenGL";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
        };

        services.picom = {
          enable = true;
          vSync = true;
          backend = "xrender"; #"glx";
        };
      })
    ];
  }
