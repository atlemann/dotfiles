{ config, lib, ... }:
with lib;

let
  cfg = config.dev.dotnet;
  user = config.attributes.mainUser.name;
  hm = config.home-manager.users."${user}";
in
  {
    options = {
      dev.dotnet = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install .NET tools";
        };
      };
    };

    config = mkIf cfg.enable {
      # Allow testing .NET compiled executables
      programs.nix-ld.enable = true;

      # Make sure dotnet finds the correct binaries
      environment.variables = {
        DOTNET_ROOT = "${hm.dev.dotnet.dotnet}/share/dotnet";
      };

      environment.systemPackages = hm.dev.dotnet.packages;

      home-manager.users."${user}".dev.dotnet.enable = true;
    };
  }
