{ config, lib, pkgs, ... }:
with lib;

let
  inherit (pkgs)
    emacsPackages
    emacsPackagesFor
    emacs
  ;
  cfg = config.emacs;
  user = config.attributes.mainUser.name;

  my_emacs =  (emacsPackagesFor emacs).emacsWithPackages (epkgs: with epkgs; [
    all-the-icons
    all-the-icons-dired
    cape
    consult
    corfu
    doom-modeline
    doom-themes
    eglot
    eglot-fsharp
    elisp-refs
    emojify
    envrc
    flycheck
    flycheck-eglot
    flymake-easy
    flymake-json
    format-all
    fsharp-mode
    git-modes
    helpful
    highlight-indent-guides
    ht
    magit
    marginalia
    markdown-preview-mode
    multiple-cursors
    nix-ts-mode
    no-littering
    orderless
    org-superstar
    projectile
    #    python-mode
    rainbow-delimiters
    restclient
    ripgrep
    rust-mode
    smartparens
    swiper
    tide
    treesit-grammars.with-all-grammars
    vertico
    vertico-posframe
    wgrep
    which-key
  ]);

in
  {
    options = {
      emacs = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install emacs";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        home-manager.users."${user}" = {
          home.packages = with pkgs; [
            my_emacs
            nodePackages.typescript-language-server
          ];
        };

        fonts = {
          packages = with pkgs; [
            emacs-all-the-icons-fonts
          ];
        };
      })
    ];
  }

