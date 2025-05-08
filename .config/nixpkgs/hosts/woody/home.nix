{ config, lib, pkgs, ... }:

let
  in
  {
    home-manager.users.aru = {
      xsession.windowManager.i3 = {
        config.assigns = {
          "3" = [{ class = "Code"; }];
          "4" = [{ class = "Slack"; }];
          "5" = [{ class = "Vivaldi-stable"; } { class = "^Chromium-browser$"; }];
          "6" = [{ class = "jetbrains-rider"; }];
          "9" = [{ class = "Vmware-view"; }];
          "10" = [{ class = "Spotify"; }];
        };

        extraConfig = ''
            # Stick worspaces to specific screens
            workspace 1 output DP-4
            workspace 2 output DP-4
            workspace 3 output DP-4
            workspace 4 output DP-4
            workspace 5 output DP-4
            workspace 6 output DP-0
            workspace 7 output DP-0
            workspace 8 output DP-0
            workspace 9 output DP-0
            workspace 10 output DP-0
          '';
      };
    };
  }
