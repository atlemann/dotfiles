{ pkgs, unstable, ... }:
let
  in
  {
    environment.systemPackages = with pkgs; [
      chromium
      dunst
      feh
      flameshot
      gnome.nautilus
      i3status-rust
      kdiff3
      pavucontrol
      pulseaudio
      rofi
      simplescreenrecorder
      slack
      spotify
      unstable.calibre
      # realpath `which copilot-agent` and symlink in ~/.local/share/JetBrains/Rider2023.1/github-copilot-intellij/copilot-agent/bin
      unstable.github-copilot-intellij-agent
      unstable.jetbrains.rider
      unstable.vivaldi
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
        displayManager = {
          lightdm.enable = true;
          setupCommands = ''
          LEFT='DP-4'
          RIGHT='DP-0'
          ${pkgs.xorg.xrandr}/bin/xrandr --output $RIGHT --primary --auto --output $LEFT --auto --left-of $RIGHT
        '';
        };
        windowManager.i3.enable = true;
        videoDrivers = ["nvidia"];
      };
    };

    # Enable sound with pipewire.
    sound.enable = true;
    hardware.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  }
