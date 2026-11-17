{ config, lib, ... }:
with lib;

let
  cfg = config.ext.networking.ssh;
in
{
  options = {
    ext.networking.ssh = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to set up the SSH client and agent";
      };
      gitlabKey.enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to use a dedicated key, ~/.ssh/id_ed25519_gitlab, for gitlab.com.
          It always goes through this machine's own agent, so detached sessions can
          push, whatever agent SSH_AUTH_SOCK points at. Create it with
          ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_gitlab.
        '';
      };
      forwardAgentTo = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "aru-ws" ];
        description = "Hosts to forward the SSH agent to, so they can use this machine's keys.";
      };
    };
  };

  config = mkIf cfg.enable {
    # Keeps SSH_AUTH_SOCK from a forwarded agent in SSH sessions.
    services.ssh-agent.enable = true;

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "*" = {
          AddKeysToAgent = "yes";
          UserKnownHostsFile = "~/.ssh/known_hosts";
          ControlMaster = "auto";
          ControlPath = "~/.ssh/master-%r@%n:%p";
          ControlPersist = "4h";
          ServerAliveInterval = 10;
        };
        "gitlab.com" = mkIf cfg.gitlabKey.enable {
          IdentityFile = "~/.ssh/id_ed25519_gitlab";
          IdentitiesOnly = "yes";
          IdentityAgent = "\${XDG_RUNTIME_DIR}/ssh-agent";
        };
      } // genAttrs cfg.forwardAgentTo (_: { ForwardAgent = "yes"; });
    };
  };
}
