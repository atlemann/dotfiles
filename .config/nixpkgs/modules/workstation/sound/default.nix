{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.sound;
  user = config.attributes.mainUser.name;
  inherit (config.wmCommon) prefix;
in
{
  options = {
    workstation.sound = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable Pulseaudio";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      users.users."${user}".extraGroups = [ "pipewire" ];

      home-manager.users."${user}" = { home.packages = with pkgs; [ alsa-utils pavucontrol ]; };

      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        pulse.enable = true;
        alsa.enable = true;
        socketActivation = true;
      };
    })
  ];
}
