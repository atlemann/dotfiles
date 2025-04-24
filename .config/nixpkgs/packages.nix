{ pkgs, ... }:

let

  in {
    # Gnome apps require dconf to remember default settings
    programs.dconf.enable = true;

    # Allow testing .NET compiled executables
    programs.nix-ld.enable = true;

    environment.systemPackages = with pkgs; [
      autorandr
      gcc
      ntfs3g
      nodejs_20
      pyright
      python3
      semgrep
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
