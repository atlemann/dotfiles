{ config, lib, pkgs, ... }:

let
  theme = import ./theme.nix;
in
{
  # There two properties are important to align home-manager with
  # global nixpkgs set.
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = false;

  home-manager.backupFileExtension = "backup";

  home-manager.users.aru = {
    home.stateVersion = config.system.stateVersion;
    home.enableNixpkgsReleaseCheck = false;

    # Home Manager needs a bit of information about you and the
    # paths it should manage.
    home.username = "aru";
    home.homeDirectory = "/home/aru";

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
