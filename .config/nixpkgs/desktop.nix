{ pkgs, ... }:
let
  in
  {
    environment.systemPackages = with pkgs; [
      dunst
      nautilus
      kdiff3
      simplescreenrecorder
      slack
      spotify
      calibre
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
