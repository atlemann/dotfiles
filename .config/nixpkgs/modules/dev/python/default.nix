{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.python;
  user = config.attributes.mainUser.name;

  # Define the core python environment
  # You can use python3.withPackages if you want global libraries,
  # but for NixOS, using 'uv' or 'poetry' for per-project deps is usually better.
  my_python = pkgs.python3;
in
  {
    options = {
      dev.python = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install Python development tools";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          my_python
          uv            # Fast Python package manager/pip replacement
          ruff          # Extremely fast Linter + Formatter
          basedpyright  # Static type checker (LSP)
          poetry        # Alternative dependency management
        ];

        home-manager.users."${user}" = {
          home.sessionPath = [ "$HOME/.local/bin" ];
          programs.bash.sessionVariables = {
            # Stops uv from downloading its own python binaries (prefers Nix)
            UV_PYTHON_DOWNLOADS = "never";
          };
        };
      })
    ];
  }
