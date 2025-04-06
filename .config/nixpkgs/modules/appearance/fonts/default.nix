{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.appearance.fonts;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      appearance.fonts = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable fonts customization.";
        };
        beautify = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable iconified patched fonts.";
        };
        antialias = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable antialiasing.";
        };
        locale = mkOption {
          type = types.str;
          default = "en_US.UTF-8";
          description = "Locale name.";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        fonts = {
          fontconfig = {
            enable = true;
            inherit (cfg) antialias;
          };
          packages = with pkgs; [
            nerd-fonts.jetbrains-mono
            font-awesome
            jetbrains-mono
          ];
          fontDir.enable = true;
          enableGhostscriptFonts = true;
          enableDefaultPackages = true;
        } // lib.optionalAttrs cfg.beautify {
          packages = with pkgs.nerd-fonts; [
            fira-code
            hack
            iosevka
            jetbrains-mono
            sauce-code-pro
          ];
        };
        i18n = { defaultLocale = cfg.locale; };
      })
    ];
  }
