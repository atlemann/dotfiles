{ config, lib, pkgs, ... }:

let
  cfg = config.ext.nix.core;
  user = config.attributes.mainUser.name;
  sources = import ../../../npins/default.nix;
in
  {
    options = {
      ext.nix.core = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable core nix setup";
        };
        gc.dates = lib.mkOption {
          type = lib.types.str;
          default = "weekly";
          description = "How often Nix GC should be run.";
        };
        gc.howold = lib.mkOption {
          type = lib.types.str;
          default = "7d";
          description = "How old store content should be to become collected by Nix GC.";
        };
        permittedInsecurePackages = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Insecure packages exceptions list";
        };
        shell.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable shell completions";
        };
      };
    };
    config = lib.mkMerge [
      (lib.mkIf cfg.enable {
        nixpkgs = {
          overlays = [
            (import sources.emacs-overlay)
          ];
          pkgs = import sources.nixpkgs {
            config = {
              allowUnfree = true;
              inherit (cfg) permittedInsecurePackages;
            };
          };
        };
        nix = {
          #    package = pkgs.nix_2_3;
          nixPath = ["nixpkgs=${sources.nixpkgs}:nixos-config=/etc/nixos/configuration.nix"];
          settings = {
            trusted-users = [ "root" "${user}" ];
            max-jobs = "auto";
            netrc-file = "/etc/nix/netrc";
          };
          extraOptions = ''
            auto-optimise-store = true
            keep-outputs = true
            keep-derivations = true
            http-connections = 10
          '';
          optimise.automatic = false;
          gc = {
            automatic = true;
            inherit (cfg.gc) dates;
            options = "--delete-older-than ${cfg.gc.howold}";
          };
        };
        environment.systemPackages = with pkgs; [
          npins
        ];
      })
      (lib.mkIf (cfg.enable && cfg.shell.enable) {
        home-manager.users."${user}" = { home.packages = with pkgs; [ nix-bash-completions ]; };
      })
    ];
  }
