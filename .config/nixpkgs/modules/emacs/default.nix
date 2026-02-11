{ config, lib, pkgs, ... }:
with lib;

let
  inherit (pkgs)
    emacsPackagesFor
    emacs
  ;
  cfg = config.emacs;

  my_emacs = (emacsPackagesFor emacs).emacsWithPackages (epkgs: with epkgs; [
    # --- UI & THEMES ---
    all-the-icons
    all-the-icons-dired
    doom-modeline
    doom-themes
    emojify
    rainbow-delimiters
    highlight-indent-guides
    org-superstar
    which-key

    # --- COMPLETION ---
    consult
    corfu
    marginalia
    orderless
    vertico
    vertico-posframe

    # --- NAVIGATION & PROJECT ---
    projectile
    # Rider-like Solution Explorer
    treemacs
    treemacs-projectile
    treemacs-magit
    treemacs-all-the-icons

    # --- RIDER-LIKE FEATURES ---
    dap-mode
    eldoc-box

    # Search tool integration
    ripgrep

    # --- DEVELOPMENT TOOLS ---
    eglot
    envrc
    flycheck
    flycheck-eglot
    flymake-easy
    flymake-json
    format-all
    git-modes
    magit
    smartparens
    wgrep

    # --- LANGUAGES ---
    nix-ts-mode
    treesit-grammars.with-all-grammars
    markdown-preview-mode
    restclient

    # --- .NET ---
    dotnet
    eglot-fsharp
    fsharp-mode
    csharp-mode

    # --- Python ---
    pyvenv
    ruff-format

    # --- Rust ---
    cargo
    flycheck-rust
    rustic

    # --- HELPER UTILS ---
    cape
    elisp-refs
    helpful
    ht
    multiple-cursors
    no-littering
    swiper
    tide
  ] ++ lib.optionals cfg.telegram.enable [
    melpaPackages.telega # Use melpa for bleeding edge
    visual-fill-column
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
        telegram.enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Telegram support in Emacs";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          my_emacs
          nixd
          nodePackages.typescript-language-server
        ] ++ (lib.optionals cfg.telegram.enable [
          # System dependencies for Telegram media/stickers
          ffmpeg
          libwebp
          imagemagick
        ]);

        fonts = {
          packages = with pkgs; [
            emacs-all-the-icons-fonts
          ];
        };
      })
    ];
  }
