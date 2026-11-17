{ config, lib, pkgs, ... }:

let
  user = config.attributes.mainUser.name;
in
{
  # There two properties are important to align home-manager with
  # global nixpkgs set.
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = false;

  home-manager.backupFileExtension = "backup";

  # The NixOS modules switch these on through home-manager.users.<user>.
  home-manager.sharedModules = [ ./hm.nix ];

  home-manager.users."${user}" = {
    inherit (config) attributes;

    home.stateVersion = config.system.stateVersion;
    home.enableNixpkgsReleaseCheck = false;

    # Home Manager needs a bit of information about you and the
    # paths it should manage.
    home.username = "${user}";
    home.homeDirectory = "/home/${user}";

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;
  };
}
