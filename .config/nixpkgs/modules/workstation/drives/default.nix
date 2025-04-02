{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.drives;
  user = config.attributes.mainUser.name;
  inherit (config.wmCommon) prefix;
in
  {
    options = {
      workstation.drives = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable detection of removable drives etc.";
        };
      };
    };

    config = mkIf cfg.enable {
      services = {
        devmon.enable = true;
        gvfs.enable = true;
        udisks2.enable = true;
      };
    };
  }
