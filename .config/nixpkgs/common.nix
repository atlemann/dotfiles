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

      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
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
