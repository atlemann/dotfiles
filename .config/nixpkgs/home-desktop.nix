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
        "notebook.lineNumbers" = "on";
        "files.autoSave" = "afterDelay";

        # Fonts
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
          }
        ];
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
