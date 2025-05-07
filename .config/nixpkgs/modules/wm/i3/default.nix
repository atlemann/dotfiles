{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.wm.i3;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      wm.i3 = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable i3.";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        services.xserver = {
          enable = true;
          windowManager.i3.enable = true;
          xkb = {
            layout = "us";
            variant = "";
          };
        };

        home-manager.users."${user}" = {
          xsession.windowManager.i3 = {
            enable = true;
            config = rec {
              menu = "${pkgs.rofi}/bin/rofi -show";
              modifier = "Mod4";
              keybindings = lib.mkOptionDefault {
                "XF86AudioRaiseVolume" = "exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ && $refresh_i3status";
                "XF86AudioLowerVolume" = "exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && $refresh_i3status";
                "XF86AudioMute"        = "exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && $refresh_i3status";

                "$mod+m+up"            = "move workspace to output up";
                "$mod+m+down"          = "move workspace to output down";
                "$mod+m+right"         = "move workspace to output next";

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
                  # fonts = {
                  #   names = [ "Jetbrains Mono" ];
                  #   size = 9.0;
                  # };

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
              };
            };
          };
        };
      })
    ];
  }
