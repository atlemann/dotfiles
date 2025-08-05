{ pkgs, ... }:
let
  in
  {
    environment.systemPackages = with pkgs; [
      nautilus
      simplescreenrecorder
      slack
      spotify
      calibre
#      vmware-horizon-client
      workrave
    ];

    services = {
      # Enable CUPS to print documents.
      printing.enable = true;
    };
  }
