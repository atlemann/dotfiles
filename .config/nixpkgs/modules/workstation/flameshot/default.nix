{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.flameshot;
  user = config.attributes.mainUser.name;
  inherit (config.wmCommon) prefix;
in
  {
    options = {
      workstation.flameshot = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable flameshot screen shotter";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}" = {
        services.flameshot = {
          enable = true;
          settings = {
            General = {
              startupLaunch = true;
              showDesktopNotification = true;
              disabledTrayIcon = false;
              showStartupLaunchMessage = false;

              # Flameshot 14 dropped the native Qt X11 grab and captures only
              # through xdg-desktop-portal, so on a bare i3/X11 session it dies
              # with `Could not locate the org.freedesktop.portal.Desktop
              # service`. Installing a portal is not a fix here: no backend
              # packaged for us implements org.freedesktop.impl.portal.Screenshot
              # outside GNOME/KDE (xdg-desktop-portal-gtk dropped it in 1.14),
              # which only turns the error into a 30s timeout. Upstream's answer
              # for minimal WMs is the legacy grab -- see
              # https://github.com/flameshot-org/flameshot/blob/master/docs/UsageX11MinimalWM.md
              useX11LegacyScreenshot = true;

              # The legacy path otherwise prompts for a monitor on every capture;
              # grab the one under the cursor instead.
              captureActiveMonitor = true;
            };
          };
        };
      };
    };
  }
