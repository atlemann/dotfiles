{ config, lib, pkgs, ... }:

let
  in
  {
    home-manager.users.aru = {
      xsession.windowManager.i3 = {
        extraConfig = ''
            # Keyboard volume control
            bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +10% && $refresh_i3status
            bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -10% && $refresh_i3status
            bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && $refresh_i3status
            bindsym $mod+m+up move workspace to output up
            bindsym $mod+m+down move workspace to output down
            bindsym $mod+m+right move workspace to output next

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

            # Assign apps to workspaces
            assign [class="jetbrains-rider"] 3
            assign [class="Code"] 4
            assign [class="Vmware-view"] 6

            assign [class="Slack"] 8
            assign [class="Vivaldi-stable"] 9
            assign [class="Google-chrome"] 9
            for_window [class="Spotify"] move to workspace 10
          '';
      };
    };
  }
