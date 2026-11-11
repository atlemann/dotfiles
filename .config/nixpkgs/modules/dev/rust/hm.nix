{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.rust;
in
  {
    options = {
      dev.rust = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to set up Rust development";
        };

        installPackages = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to install the tools in `packages` into the home profile,
            and point rust-analyzer at the standard library source. NixOS hosts
            do both system-wide instead.
          '';
        };

        packages = mkOption {
          type = types.listOf types.package;
          readOnly = true;
          internal = true;
          default = with pkgs; [
            rustup           # Manage toolchains (stable, nightly, etc.)
            rust-analyzer    # Language Server
            bacon            # Background code checker
            cargo-expand     # Useful for macro debugging
            
            # Essential build dependencies for many common crates
            pkg-config
            openssl
            gcc
          ];
        };

        # Ensure rust-analyzer can find the source code for standard libraries
        variables = mkOption {
          type = types.attrsOf types.str;
          readOnly = true;
          internal = true;
          default = {
            RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
          };
        };
      };
    };

    config = mkIf cfg.enable (mkMerge [
      {
        home.sessionPath = [ "$HOME/.cargo/bin" ];
      }
      (mkIf cfg.installPackages {
        home.packages = cfg.packages;
        home.sessionVariables = cfg.variables;
      })
    ]);
  }
