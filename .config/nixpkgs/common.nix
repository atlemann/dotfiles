{ config, lib, pkgs, ... }:

  let
    sources = import ./npins/default.nix;
  in
    {
      documentation.enable = false;

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
