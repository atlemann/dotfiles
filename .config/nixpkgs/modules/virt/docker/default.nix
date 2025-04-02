{ config, inputs, lib, pkgs, ... }:
with lib;

let
  cfg = config.ext.virtualization.docker.core;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      ext.virtualization.docker.core = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Docker core setup";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        virtualisation.docker = {
          enable = true;
          enableOnBoot = false;
        };

        users.users."${user}".extraGroups = [ "docker" ];

        networking.dhcpcd.denyInterfaces = [ "docker*" ];

        home-manager.users."${user}" = {
          home.packages = with pkgs; [
            ctop
            dive
            lazydocker
            libcgroup
          ];
        };
        shell.prompts.starship.modulesConfiguration = { docker_context = { format = "via [🐋 $context](blue bold)"; }; };
      })
    ];
  }
