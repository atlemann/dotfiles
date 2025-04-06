{ pkgs, ... }:
let
  in
  {
    environment.systemPackages = with pkgs; [
      chromium
      dunst
      nautilus
      kdiff3
      simplescreenrecorder
      slack
      spotify
      calibre
      vivaldi
      vmware-horizon-client
      workrave
    ];

    services = {
      # Enable CUPS to print documents.
      printing.enable = true;
    };

    # USB automount
    services.gvfs.enable = true;
  }
