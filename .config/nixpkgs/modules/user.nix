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
      ];
    };

    # Set your time zone.
    time.timeZone = "Europe/Oslo";

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";
  }
