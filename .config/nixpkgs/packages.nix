{ pkgs, ... }:

let

  in {
    environment.systemPackages = with pkgs; [
      ntfs3g
    ];
  }
