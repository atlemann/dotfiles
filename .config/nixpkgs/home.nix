{ config, lib, pkgs, ... }:

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
    flameshot
    font-awesome
    htop
    jetbrains.rider
    slack
    spotify
    vivaldi
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

  xsession.windowManager.i3 = {
    enable = true;
    config = rec {
      modifier = "Mod4";
      keybindings = lib.mkOptionDefault {
        "Print" = "exec \"flameshot gui\"";
        "${modifier}+d" = "exec --no-startup-id ${pkgs.rofi}/bin/rofi -show run";
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
}
