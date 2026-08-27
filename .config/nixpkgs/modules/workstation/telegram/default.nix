{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.telegram;
in
  {
    options = {
      workstation.telegram = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Telegram (telega) in Emacs";
        };
      };
    };

    config = mkIf cfg.enable {
      # Telega needs these for media support (stickers, avatars, video messages)
      environment.systemPackages = with pkgs; [
        tdlib        # The core telegram library
        libwebp      # For animated stickers
        ffmpeg       # For video/voice message playback
        imagemagick  # For image processing
      ];
    };
  }
