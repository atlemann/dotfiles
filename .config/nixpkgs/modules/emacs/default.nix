{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.emacs;
  user = config.attributes.mainUser.name;
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
    home-manager.users."${user}" = {
      programs.emacs = {
        enable = true;
        package = pkgs.emacsWithPackagesFromUsePackage {
          config = ../../../../.emacs.d/configuration.org;
          package = pkgs.emacs;
          alwaysEnsure = true;
          alwaysTangle = true;
          extraEmacsPackages = epkgs: with epkgs; [
            treesit-grammars.with-all-grammars
          ] ++ lib.optionals cfg.telegram.enable [
            melpaPackages.telega
            visual-fill-column
          ];
        };
      };

      home.file.".emacs.d/init.el".text = ''
        (org-babel-load-file
          (expand-file-name "configuration.org" user-emacs-directory))
      '';
    };

    environment.systemPackages = with pkgs; [
      nixd
    ];

    fonts.packages = with pkgs; [
      emacs-all-the-icons-fonts
    ];
  };
}
