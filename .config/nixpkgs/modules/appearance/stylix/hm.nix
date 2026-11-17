{ config, lib, ...}:

let
  cfg = config.appearance.stylix;
in
  {
    options.appearance.stylix = { enable = lib.mkEnableOption "stylix"; };

    # The stylix options come from the system stylix module on NixOS hosts, and
    # from stylix's home-manager module elsewhere.
    config = lib.mkIf cfg.enable {
      stylix = {
        enable = true;
        autoEnable = true;
        targets.rofi.enable = false;
        targets.emacs.enable = false;
      };

      # Disable mako (Wayland notifier thing) due to deprecation errors
      stylix.targets.mako.enable = false;
    };
  }
