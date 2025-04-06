{ config, lib, pkgs, ... }:

  let
    sources = import ./npins/default.nix;
  in
    {
      documentation.enable = false;

      console = {
        keyMap = "us";
      };
    }
