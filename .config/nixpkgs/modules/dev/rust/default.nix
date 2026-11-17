{ config, lib, ... }:
with lib;

let
  cfg = config.dev.rust;
  user = config.attributes.mainUser.name;
  hm = config.home-manager.users."${user}";
in
  {
    options = {
      dev.rust = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install Rust development tools";
        };
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = hm.dev.rust.packages;
      environment.variables = hm.dev.rust.variables;

      home-manager.users."${user}".dev.rust.enable = true;
    };
  }
