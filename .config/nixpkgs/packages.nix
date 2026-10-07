{ pkgs, ... }:

let

  in {
    # Gnome apps require dconf to remember default settings
    programs.dconf.enable = true;

    environment.systemPackages = with pkgs; [
      autorandr
      ntfs3g
    ];
  }
