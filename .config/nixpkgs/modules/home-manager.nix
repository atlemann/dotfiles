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

  home-manager.users."${user}" = {
    home.stateVersion = config.system.stateVersion;
    home.enableNixpkgsReleaseCheck = false;

    # Home Manager needs a bit of information about you and the
    # paths it should manage.
    home.username = "${user}";
    home.homeDirectory = "/home/${user}";

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;

    programs.bash = {
      sessionVariables = {
        PATH = "$PATH:/home/aru/.dotnet/tools";
      };
    };

    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
    };
  };
}
