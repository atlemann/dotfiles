{ config, lib, pkgs, ... }:

let
  nixGL = import <nixgl> {};
in
{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "aru";
  home.homeDirectory = "/home/aru";

  nixpkgs.config = {
    allowUnfree = true;
  };

  home.packages = with pkgs; [
    bottom
    direnv
    dotnet-sdk
    emacs
    font-awesome
    htop
    jetbrains.rider

    # TODO: make a flake for nix-channel --add https://github.com/guibou/nixGL/archive/main.tar.gz nixgl && nix-channel --update
    nixGL.auto.nixGLDefault

    slack
    spotify
    vscode
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "22.05";

  home.sessionVariables = {
    DOTNET_ROOT = "$(dirname $(realpath $(which dotnet)))";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  services.dunst = {
    enable = true;
  };

  services.flameshot = {
    enable = true;
    settings = {
      General = {
        startupLaunch = true;
        showDesktopNotification = true;
        disabledTrayIcon = false;
        showStartupLaunchMessage = false;
      };
    };
  };

  xsession.windowManager.i3 = {
    enable = true;
    config = rec {
      modifier = "Mod4";
      keybindings = lib.mkOptionDefault {
        "Print" = "exec \"flameshot gui\"";
        "${modifier}+Return" = "exec nixGL alacritty";
        "${modifier}+d" = "exec --no-startup-id ${pkgs.rofi}/bin/rofi -show run";
        "${modifier}+q" = "split toggle";
      };
      bars = [
        {
          fonts = {
            size = 10.0;
          };

          statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ${~/.config/i3status-rust/config-options.toml}";
        }
      ];
    };

    extraConfig = ''
        # Keyboard volume control
        bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +10% && $refresh_i3status
        bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -10% && $refresh_i3status
        bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && $refresh_i3status

        # MRU-ish workspace switching by pressing same number again
        workspace_auto_back_and_forth yes

        # Stick worspaces to specific screens
        workspace 1 output DVI-I-2
        workspace 2 output DVI-I-2
        workspace 3 output DVI-I-2
        workspace 4 output DVI-I-2
        workspace 5 output DVI-I-2
        workspace 6 output DVI-I-3
        workspace 7 output DVI-I-3
        workspace 8 output DVI-I-3
        workspace 9 output DVI-I-3
        workspace 10 output DVI-I-3

        # Assign apps to workspaces
        assign [class="Vivaldi-stable"] 4
        assign [class="Google-chrome"] 4
        assign [class="Slack"] 5
        assign [class="Code"] 6
        assign [class="jetbrains-rider"] 7
        assign [class="Vmware-view"] 7
        for_window [class="Spotify"] move to workspace 8
      '';
  };

  programs.i3status-rust = {
    enable = true;
    bars = {
      options = {
        icons = "awesome";
        theme = "gruvbox-dark";
      };
    };
  };

  programs.rofi = {
    enable = true;
    theme = "gruvbox-dark";
  }; 

  programs.chromium = {
    enable = true;
    package = pkgs.vivaldi;
    extensions = [
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
    ];
  };

  programs.alacritty = {
    enable = true;
  };
}
