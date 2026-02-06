{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.rust;
  user = config.attributes.mainUser.name;
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

    config = mkMerge [
      (mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          rustup           # Manage toolchains (stable, nightly, etc.)
          rust-analyzer    # Language Server
          bacon            # Background code checker
          cargo-expand     # Useful for macro debugging
          
          # Essential build dependencies for many common crates
          pkg-config
          openssl
          gcc
        ];

        # Ensure rust-analyzer can find the source code for standard libraries
        environment.variables = {
          RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
        };

        home-manager.users."${user}" = {
          programs.bash.sessionVariables = {
            # Add cargo binaries to path
            PATH = "$PATH:$HOME/.cargo/bin";
          };
        };
      })
    ];
  }
