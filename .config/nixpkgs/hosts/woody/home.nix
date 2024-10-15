{ config, lib, pkgs, ... }:

let
  in
  {
    imports =
      [
        ../../home.nix
      ];

    home-manager.users.aru = {
      xsession.windowManager.i3 = {
        extraConfig = ''
            # Keyboard volume control
            bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +10% && $refresh_i3status
            bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -10% && $refresh_i3status
            bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && $refresh_i3status

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

            # Assign apps to workspaces
            assign [class="jetbrains-rider"] 6
            assign [class="Code"] 4
            assign [class="Vmware-view"] 9

            assign [class="Slack"] 4
            assign [class="Vivaldi-stable"] 5
            assign [class="Google-chrome"] 5
            for_window [class="Spotify"] move to workspace 10
          '';
      };
    };
  }
