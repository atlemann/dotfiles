{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.ext.networking.ssh;
  user = config.attributes.mainUser.name;
  publicKeys = import ./public-keys.nix;
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
      gitlabKey.enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to use a dedicated key for gitlab.com; see the home-manager option.";
      };
      forwardAgentTo = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "aru-ws" ];
        description = "Hosts to forward the SSH agent to, so they can use this machine's keys.";
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

      # Trust the other machines' keys. This is additive to ~/.ssh/authorized_keys.
      users.users."${user}".openssh.authorizedKeys.keys =
        attrValues (removeAttrs publicKeys [ config.networking.hostName ]);

      # home-manager's ssh-agent is the agent; gcr would otherwise start with
      # gnome-keyring and compete for SSH_AUTH_SOCK.
      services.gnome.gcr-ssh-agent.enable = false;

      home-manager.users."${user}".ext.networking.ssh = {
        enable = true;
        inherit (cfg) gitlabKey forwardAgentTo;
      };
    })
  ];
}
