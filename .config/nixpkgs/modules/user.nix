{ config, lib, pkgs, ... }:

let
  user = config.attributes.mainUser.name;
in
  {
    users.users."${user}" = {
      isNormalUser = true;
      description = config.attributes.mainUser.fullName;
      extraGroups = [
        "wheel"
        "libvirtd"
        "docker"
      ];
    };
  }
