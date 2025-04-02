{ pkgs, ... }:
let
  in
  {
    environment.systemPackages = with pkgs; [
      chromium
      dunst
      feh
      flameshot
      nautilus
      i3status-rust
      kdiff3
      rofi
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
      picom = {
        enable = true;
        vSync = true;
        backend = "xrender"; #"glx";
      };

      # Configure keymap in X11
      xserver.xkb = {
        layout = "us";
        variant = "";
      };

      # Enable CUPS to print documents.
      printing.enable = true;

      # Enable the X11 windowing system.
      xserver = {
        enable = true;
        windowManager.i3.enable = true;
      };
    };

    # Graphics for alacritty
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # USB automount
    services.gvfs.enable = true;
  }
