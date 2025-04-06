{ pkgs, ... }:
let
  in
  {
    environment.systemPackages = with pkgs; [
      chromium
      dunst
      feh
      nautilus
      kdiff3
      simplescreenrecorder
      slack
      spotify
      calibre
      # realpath `which copilot-agent` and symlink in ~/.local/share/JetBrains/Rider2023.1/github-copilot-intellij/copilot-agent/bin
      github-copilot-intellij-agent
      jetbrains.rider
      vivaldi
      vmware-horizon-client
      vscode
      workrave
    ];

    services = {
      # Enable CUPS to print documents.
      printing.enable = true;
    };

    # USB automount
    services.gvfs.enable = true;
  }
