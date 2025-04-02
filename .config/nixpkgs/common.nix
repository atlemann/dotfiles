{ config, lib, pkgs, ... }:

  let
    sources = import ./npins/default.nix;
  in
    {
      documentation.enable = false;

      boot = {
        # This is required for dotnet to run correctly
        kernel.sysctl."fs.inotify.max_user_instances" = 524288;
      };

      # Set your time zone.
      time.timeZone = "Europe/Oslo";

      # Select internationalisation properties.
      i18n.defaultLocale = "en_US.UTF-8";

      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
      };

      services = {
        # Support removable drives and such
        devmon.enable = true;
        gvfs.enable = true;
        udisks2.enable = true;
      };

      console = {
        keyMap = "us";
      };

      fonts = {
        fontconfig = {
          enable = true;
          antialias = true;
        };
        packages = with pkgs; [
          emacs-all-the-icons-fonts
          nerd-fonts.jetbrains-mono
          font-awesome
          jetbrains-mono
        ];
      };
    }
