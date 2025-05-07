{ config, lib, pkgs, ... }:

let
  in
  {
    home-manager.users.aru = {
      xsession.windowManager.i3 = {
        config.assigns = {
          "3" = [{ class = "jetbrains-rider"; }];
          "4" = [{ class = "Code"; }];
          "6" = [{ class = "Vmware-view"; }];
          "8" = [{ class = "Slack"; }];
          "9" = [{ class = "Vivaldi-stable"; } { class = "^Chromium-browser$"; }];
          "10" = [{ class = "Spotify"; }];
        };

        extraConfig = ''
            # Stick worspaces to specific screens
            workspace 1 output DP-6
            workspace 2 output DP-6
            workspace 3 output DP-6
            workspace 4 output DP-6
            workspace 5 output DP-6
            workspace 6 output DP-6
            workspace 7 output DP-4
            workspace 8 output DP-4
            workspace 9 output DP-4
            workspace 10 output DP-4
          '';
      };
    };
  }
