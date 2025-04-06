{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.dotnet;
  user = config.attributes.mainUser.name;
  my_dotnet = with pkgs.dotnetCorePackages; (combinePackages [
    sdk_8_0
    runtime_8_0
    sdk_9_0
    runtime_9_0
  ]);
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

    config = mkMerge [
      (mkIf cfg.enable {
        # Make sure dotnet finds the correct binaries
        environment.variables = {
          DOTNET_ROOT = my_dotnet;
        };

        boot = {
          # This is required for dotnet to run correctly
          kernel.sysctl."fs.inotify.max_user_instances" = 524288;
        };

        home-manager.users."${user}" = {
          programs.bash = {
            sessionVariables = {
              PATH = "$PATH:/home/aru/.dotnet/tools";
            };
          };
          home.packages = with pkgs; [
            my_dotnet
            csharp-ls
            (fsautocomplete.overrideDerivation (o: { dotnet-runtime = my_dotnet; }))
          ];
        };
      })
    ];
  }
