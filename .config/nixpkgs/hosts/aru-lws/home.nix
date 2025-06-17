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
      };
    };
  }
