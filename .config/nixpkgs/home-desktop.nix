{ config, lib, pkgs, ... }:

let
  theme = import ./theme.nix;
in
  {
    imports =
      [
        ./home-common.nix
      ];

  home-manager.users.aru = {

    programs.rofi = {
      enable = true;
      theme = theme.name;
      extraConfig = {
        modi = "combi";
        show-icons = true;
        hide-scrollbar = true;
      };
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

    programs.feh.enable = true;

    programs.vscode = {
      enable = true;
      mutableExtensionsDir = false;
      extensions = with pkgs.vscode-extensions; [
        eamodio.gitlens
        humao.rest-client
        ionide.ionide-fsharp
        jdinhlife.gruvbox
        mhutchie.git-graph
        ms-dotnettools.csharp
        ms-dotnettools.vscode-dotnet-runtime
        ms-vscode-remote.remote-ssh
      ];
      userSettings = {
        "workbench.colorTheme" = "Gruvbox Dark Medium";
        "notebook.lineNumbers" = "on";
        "files.autoSave" = "afterDelay";

        # Fonts
        "editor.fontFamily" = "Jetbrains Mono";
        "editor.fontSize" = 14;
        "editor.fontLigatures" = true;

        # Whitespace
        "editor.renderWhitespace" = "all";
        "files.trimTrailingWhitespace" = true;
        "files.trimFinalNewlines" = true;
        "files.insertFinalNewline" = true;

        # F#
        "FSharp.inlayHints.typeAnnotations" = false;
        "FSharp.inlayHints.parameterNames" = false;
        "FSharp.inlayHints.enabled" = false;
      };
    };

    xsession.windowManager.i3 = {
      enable = true;
      config = rec {
        menu = "${pkgs.rofi}/bin/rofi -show";
        modifier = "Mod4";
        keybindings = lib.mkOptionDefault {
          "Print" = "exec \"flameshot gui\"";
          "${modifier}+Return" = "exec alacritty";
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

            statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config-options.toml";

            # Gruvbox-dark: https://github.com/jmattheis/i3wm-gruvbox-dark
            colors = {
              background = theme.black;
              statusline = theme.lightgray;
              focusedWorkspace = {
                background = theme.lightgray;
                border = theme.lightgray;
                text = theme.black;
              };
              inactiveWorkspace =  {
                background = theme.darkgray;
                border = theme.darkgray;
                text = theme.lightgray;
              };
              activeWorkspace = {
                background = theme.darkgray;
                border = theme.darkgray;
                text = theme.lightgray;
              };
              urgentWorkspace = {
                background = theme.red;
                border = theme.red;
                text = theme.black;
              };
            };
          }
        ];
        colors = {
          background = theme.black;
          focused = {
            background = theme.lightgray;
            border = theme.lightgray;
            childBorder = theme.darkgray;
            indicator = theme.magenta;
            text = theme.black;
          };
          focusedInactive = {
            background = theme.darkgray;
            border = theme.darkgray;
            childBorder = theme.darkgray;
            indicator = theme.magenta;
            text = theme.lightgray;
          };
          # placeholder = {
          #   background = "#0c0c0c";
          #   border = "#000000";
          #   childBorder = "#0c0c0c";
          #   indicator = "#000000";
          #   text = "#ffffff";
          # };
          unfocused = {
            background = theme.darkgray;
            border = theme.darkgray;
            childBorder = theme.darkgray;
            indicator = theme.magenta;
            text = theme.lightgray;
          };
          urgent = {
            background = theme.red;
            border = theme.red;
            childBorder = theme.red;
            indicator = theme.red;
            text = theme.white;
          };
        };
        startup = [
        ];
      };
    };

    programs.i3status-rust = {
      enable = true;
      bars = {
        options = {
          icons = "awesome6";
          theme = theme.name;
        };
      };
    };
  };
}
