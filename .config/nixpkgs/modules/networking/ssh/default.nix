{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.ext.networking.ssh;
  user = config.attributes.mainUser.name;
in
{
  options = {
    ext.networking.ssh = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable SSH functionality";
      };
      X11Forwarding = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable X11 forwarding";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      services.openssh = {
        enable = true;
        allowSFTP = true;
        settings.X11Forwarding = cfg.X11Forwarding;
        startWhenNeeded = true;
      };
      programs.ssh.askPassword = "${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass";

      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
      };

      # home-manager.users."${user}" = {
      #   programs.ssh = {
      #     enable = true;
      #     forwardAgent = true;
      #     userKnownHostsFile = "~/.ssh/known_hosts";
      #     controlMaster = "auto";
      #     controlPath = "~/.ssh/sockets/%r@%h:%p";
      #     controlPersist = "4h";
      #     serverAliveInterval = 10;
      #   };
      # };
    })
  ];
}
