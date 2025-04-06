{ pkgs, ... }:

let

  in {
    # Gnome apps require dconf to remember default settings
    programs.dconf.enable = true;

    # Allow testing .NET compiled executables
    programs.nix-ld.enable = true;

    environment.systemPackages = with pkgs; [
      autorandr
      bottom
      curl
      dconf
      gcc
      git
      htop
      lsd
      ntfs3g
      nixos-option
      nodejs_20
      npins
      pciutils
      pqrs
      pyright
      python3
      ripgrep
      semgrep
      udiskie
      udisks
      usbutils
      yarn

      # Rust packages
      # (fenix.complete.withComponents [
      #   "cargo"
      #   "clippy"
      #   "rust-src"
      #   "rustc"
      #   "rustfmt"
      # ])

      rustc
      rustup
      rust-analyzer

      # NixOS helpers
      (writeShellScriptBin "nixos-switch" (builtins.readFile ./nixos-switch.sh))
    ];
  }
