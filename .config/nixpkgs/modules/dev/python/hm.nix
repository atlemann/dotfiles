{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.python;

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
          description = "Whether to set up Python development";
        };

        installPackages = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to install the tools in `packages` into the home profile.
            NixOS hosts install them system-wide instead.
          '';
        };

        packages = mkOption {
          type = types.listOf types.package;
          readOnly = true;
          internal = true;
          default = with pkgs; [
            my_python
            uv            # Fast Python package manager/pip replacement
            ruff          # Extremely fast Linter + Formatter
            basedpyright  # Static type checker (LSP)
            poetry        # Alternative dependency management
          ];
        };
      };
    };

    config = mkIf cfg.enable (mkMerge [
      {
        home.sessionPath = [ "$HOME/.local/bin" ];
        programs.bash.sessionVariables = {
          # Stops uv from downloading its own python binaries (prefers Nix)
          UV_PYTHON_DOWNLOADS = "never";
        };
      }
      (mkIf cfg.installPackages {
        home.packages = cfg.packages;
      })
    ]);
  }
