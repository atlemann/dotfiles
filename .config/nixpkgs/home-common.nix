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
      enable = true;
      sessionVariables = {
        PATH = "$PATH:/home/aru/.dotnet/tools";
      };
    };

    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
    };

    programs.git = {
      enable = true;
      userName = "Atle Rudshaug";
      userEmail = "atle.rudshaug@gmail.com";
      aliases = {
        co = "checkout";
        cob = "checkout -b";
        ci = "commit";
        st = "status";
        br = "branch";
        bra = "branch -a";
        hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";
        ec = "config --global -e";
      };
      extraConfig = {
        merge = {
          tool = "kdiff3";
        };
        mergetool = {
          kdiff3 = {
            trustExitCode = false;
          };
        };
        diff = {
          guitool = "kdiff3";
        };
        difftool = {
          kdiff3 = {
            trustExitCode = false;
          };
        };
      };
    };
  };
}
