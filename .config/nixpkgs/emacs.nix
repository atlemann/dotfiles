{ pkgs }:

let
  inherit (pkgs)
    emacsPackages
    emacsPackagesFor
    emacs29
  ;

  in
  (emacsPackagesFor emacs29).emacsWithPackages (epkgs: with epkgs; [
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
    python-mode
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
  ])
