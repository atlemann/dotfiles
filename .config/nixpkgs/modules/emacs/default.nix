{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.emacs;
  user = config.attributes.mainUser.name;
  hm = config.home-manager.users."${user}";
in {
  options = {
    emacs = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to install emacs";
      };
      telegram.enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable Telegram support in Emacs";
      };
    };
  };

  config = mkIf cfg.enable {
    home-manager.users."${user}".emacs = {
      enable = true;
      inherit (cfg) telegram;
    };

    environment.systemPackages = hm.emacs.packages;

    fonts.packages = with pkgs; [
      emacs-all-the-icons-fonts
    ];
  };
}
