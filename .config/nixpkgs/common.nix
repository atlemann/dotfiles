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
    }
