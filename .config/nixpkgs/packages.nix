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
      nodejs_22
      semgrep
      yarn
    ];
  }
