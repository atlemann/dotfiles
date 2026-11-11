{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.emacs;
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

      installPackages = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to install the tools in `packages` into the home profile.
          NixOS hosts install them system-wide instead.
        '';
      };

      packages = mkOption {
        type = types.listOf types.package;
        readOnly = true;
        internal = true;
        default = with pkgs; [
          emacs-lsp-booster  # used by eglot-booster
          nixd
        ];
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      programs.emacs = {
        enable = true;
        package = pkgs.emacsWithPackagesFromUsePackage {
          config = ../../../../.emacs.d/configuration.org;
          package = pkgs.emacs;
          alwaysEnsure = true;
          alwaysTangle = true;
          extraEmacsPackages = epkgs: with epkgs; [
            treesit-grammars.with-all-grammars
            (trivialBuild {
              pname = "magit-glab";
              version = "0.1.0";
              src = ./magit-glab;
              packageRequires = [ magit markdown-mode transient ];
            })
          ] ++ lib.optionals cfg.telegram.enable [
            melpaPackages.telega
            visual-fill-column
          ];
        };

        # X11 Emacs paints its own mouse pointer and defaults it to black,
        # which is invisible against a dark background. Keep the pointer on
        # whatever the active theme uses as its foreground.
        extraConfig = ''
          (defun aru/sync-mouse-color (&optional frame)
            "Point FRAME's mouse cursor at the default face foreground."
            (when (display-graphic-p frame)
              (let ((fg (face-attribute 'default :foreground frame)))
                (when (stringp fg)
                  (set-frame-parameter frame 'mouse-color fg)))))

          (add-hook 'after-make-frame-functions #'aru/sync-mouse-color)
          (add-hook 'enable-theme-functions
                    (lambda (&rest _) (aru/sync-mouse-color)))
          (aru/sync-mouse-color)
        '';
      };

      home.file.".emacs.d/init.el".text = ''
        ;;; init.el -*- lexical-binding: t; -*-
        (org-babel-load-file
          (expand-file-name "configuration.org" user-emacs-directory))
      '';
    }
    (mkIf cfg.installPackages {
      home.packages = cfg.packages;
    })
  ]);
}
