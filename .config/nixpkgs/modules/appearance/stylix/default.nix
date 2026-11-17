{ config, lib, pkgs, ...}:

let
  cfg = config.appearance.stylix;
  user = config.attributes.mainUser.name;
in
  {
    options.appearance.stylix = { enable = lib.mkEnableOption "stylix"; };

    config = lib.mkIf cfg.enable {
      home-manager.users."${user}" = {
        appearance.stylix.enable = true;
        home.packages = with pkgs; [
          feh
        ];
      };

      stylix = import ./theme.nix pkgs // {
        enable = true;
        autoEnable = true;
        targets.kmscon.enable = false;
      };
    };
  }
