{ config, lib, pkgs, ... }:

let
  niv = import ./nix/sources.nix;
  unstable = import niv.unstable { config.allowUnfree = true; };
  nixGL = import niv.nixGL {};

  # gruvbox-dark colors

  # https://github.com/jmattheis/i3wm-gruvbox-dark
  darkgray = "#1d2021";
  lightgray = "#bdae93";

  # https://github.com/eendroroy/alacritty-theme/blob/master/themes/gruvbox_dark.yaml
  black =  "#282828";
  red =    "#cc241d";
  green =  "#98971a";
  yellow = "#d79921";
  blue =   "#458588";
  magenta ="#b16286";
  cyan =   "#689d6a";
  white =  "#a89984";

  bright.black =  "#928374";
  bright.red =    "#fb4934";
  bright.green =  "#b8bb26";
  bright.yellow = "#fabd2f";
  bright.blue =   "#83a598";
  bright.magenta ="#d3869b";
  bright.cyan =   "#8ec07c";
  bright.white =  "#ebdbb2";

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
    curl
    dotnet-sdk
    emacs-all-the-icons-fonts
    fira-code
    font-awesome
    jetbrains-mono # Font
    jetbrains.rider

    # TODO: make a flake for nix-channel --add https://github.com/guibou/nixGL/archive/main.tar.gz nixgl && nix-channel --update
    nixGL.auto.nixGLDefault

    pqrs

    slack
    spotify

    tree

    vmware-horizon-client

    # Required for Avalonia
    fontconfig
    xorg.libICE
    xorg.libSM
    xorg.libX11
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "23.05";

  home.sessionVariables = {
    NIX_PATH="${config.home.homeDirectory}/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels"; #${NIX_PATH:+:$NIX_PATH}";
    DOTNET_ROOT = "$(dirname $(realpath $(which dotnet)))";
    SSH_AUTH_SOCK = "\${SSH_AUTH_SOCK:-$XDG_RUNTIME_DIR/ssh-agent.socket}";
    LD_LIBRARY_PATH = "\$LD_LIBRARY_PATH:${lib.strings.makeLibraryPath [ pkgs.fontconfig pkgs.xorg.libICE pkgs.xorg.libSM pkgs.xorg.libX11 ]}";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  fonts.fontconfig.enable = true;

  services.emacs = {
    enable = true;
    client.enable = true;
    defaultEditor = true;
  };

  programs.emacs.enable = true;
  
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

  services.picom = {
    enable = true;
    vSync = true;
    backend = "xrender";
  };

  xsession = {
    enable = true;
  };

  xsession.windowManager.i3 = {
    enable = true;
    config = rec {
      menu = "${pkgs.rofi}/bin/rofi -show";
      modifier = "Mod4";
      keybindings = lib.mkOptionDefault {
        "Print" = "exec \"flameshot gui\"";
        "${modifier}+Return" = "exec nixGL alacritty";
        "${modifier}+q" = "split toggle";
        "${modifier}+h" = "focus left";
        "${modifier}+j" = "focus down";
        "${modifier}+k" = "focus up";
        "${modifier}+l" = "focus right";
      };
      workspaceAutoBackAndForth = true;
      bars = [
        {
          fonts = {
            names = [ "Jetbrains Mono" ];
            size = 9.0;
          };

          statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ${~/.config/i3status-rust/config-options.toml}";

          # Gruvbox-dark: https://github.com/jmattheis/i3wm-gruvbox-dark
          colors = {
            background = black;
            statusline = lightgray;
            focusedWorkspace = {
              background = lightgray;
              border = lightgray;
              text = black;
            };
            inactiveWorkspace =  {
              background = darkgray;
              border = darkgray;
              text = lightgray;
            };
            activeWorkspace = {
              background = darkgray;
              border = darkgray;
              text = lightgray;
            };
            urgentWorkspace = {
              background = red;
              border = red;
              text = black;
            };
          };
        }
      ];
      colors = {
        background = black;
        focused = {
          background = lightgray;
          border = lightgray;
          childBorder = darkgray;
          indicator = magenta;
          text = black;
        };
        focusedInactive = {
          background = darkgray;
          border = darkgray;
          childBorder = darkgray;
          indicator = magenta;
          text = lightgray;
        };
        # placeholder = {
        #   background = "#0c0c0c";
        #   border = "#000000";
        #   childBorder = "#0c0c0c";
        #   indicator = "#000000";
        #   text = "#ffffff";
        # };
        unfocused = {
          background = darkgray;
          border = darkgray;
          childBorder = darkgray;
          indicator = magenta;
          text = lightgray;
        };
        urgent = {
          background = red;
          border = red;
          childBorder = red;
          indicator = red;
          text = white;
        };
      };
      startup = [
        { command = "systemctl --user import-environment XAUTHORITY DISPLAY"; notification = false; } # Required for picom to start
        { command = "systemctl --user restart picom.service"; notification = false; } # The line above seems not to be enough, so adding this as well
        { command = "${pkgs.feh}/bin/feh --no-fehbg --bg-fill '${config.home.homeDirectory}/.dotfiles/wallpapers/wp11058332-gruvbox-wallpapers.png'"; notification = false; }
      ];
    };
    extraConfig = ''
        # Keyboard volume control
        bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +10% && $refresh_i3status
        bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -10% && $refresh_i3status
        bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && $refresh_i3status

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
        assign [class="Vmware-view"] 8
        for_window [class="Spotify"] move to workspace 9
      '';
  };

  programs.i3status-rust = {
    enable = true;
    bars = {
      options = {
        icons = "awesome6";
        theme = "gruvbox-dark";
      };
    };
  };

  programs.rofi = {
    enable = true;
    theme = "gruvbox-dark";
    extraConfig = {
      modi = "combi";
      show-icons = true;
      hide-scrollbar = true;
    };
  };

  programs.feh.enable = true;

  programs.chromium = {
    enable = true;
    package = pkgs.vivaldi;
    extensions = [
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
      { id = "gfbliohnnapiefjpjlpjnehglfpaknnc"; } # Surfingkeys
    ];
  };

  programs.firefox = {
    enable = true;
  };

  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        opacity = 0.9;
      };
      font = {
        normal.family = "Jetbrains Mono";
        size = 10;
      };
      colors = {
        primary = {
          background = black;
          foreground = white;
        };
        normal = {
          black = black;
          red = red;
          green = green;
          yellow = yellow;
          blue = blue;
          magenta = magenta;
          cyan = cyan;
          white = white;
        };
        bright = {
          black = bright.black;
          red = bright.red;
          green = bright.green;
          yellow = bright.yellow;
          blue = bright.blue;
          magenta = bright.magenta;
          cyan = bright.cyan;
          white = bright.white;
        };
      };
    };
  };

  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      eamodio.gitlens
      humao.rest-client
      ionide.ionide-fsharp
      jdinhlife.gruvbox
      mhutchie.git-graph
      ms-dotnettools.csharp
      ms-vscode-remote.remote-ssh
    ];
    userSettings = {
      "workbench.colorTheme" = "Gruvbox Dark Medium";
      "editor.fontLigatures" = true;
      "editor.fontFamily" = "Jetbrains Mono";
      "editor.fontSize" = 14;
      "notebook.lineNumbers" = "on";
      "files.autoSave" = "afterDelay";
      "FSharp.inlayHints.typeAnnotations" = false;
      "FSharp.inlayHints.parameterNames" = false;
      "FSharp.inlayHints.enabled" = false;
    };
  };

  programs.git = {
    enable = true;
    userName = "Atle Rudshaug";
    userEmail = "atle.rudshaug@gmail.com";
    aliases = {
      co = "checkout";
      cob = "checkout -b";
      ci = "commit";
      st = "status";
      br = "branch";
      bra = "branch -a";
      hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";
      ec = "config --global -e";
    };
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.bottom.enable = true;
  programs.htop.enable = true;
}
