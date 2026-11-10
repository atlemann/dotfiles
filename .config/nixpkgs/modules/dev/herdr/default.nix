{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.herdr;

  user = config.attributes.mainUser.name;

  tomlFormat = pkgs.formats.toml { };

  reviewr = pkgs.callPackage ./reviewr.nix { };
in
  {
    options = {
      dev.herdr = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to install herdr, a terminal workspace manager for AI coding agents.

            Also enables dev.claudecode by default, since that is the agent herdr
            is mostly used with here. herdr itself is agent-agnostic, so set
            dev.claudecode.enable = false to opt out.
          '';
        };

        settings = mkOption {
          type = tomlFormat.type;
          default = {
            onboarding = false;
            ui.toast.delivery = "system";
            theme = {
              name = "gruvbox";
              auto_switch = false;
            };
            keys.command = [
              {
                key = "prefix+d";
                type = "plugin_action";
                command = "persiyanov.reviewr.toggle";
              }
            ];
          };
          description = ''
            Contents of ~/.config/herdr/config.toml.

            Managed on every host, because `herdr --remote` takes keybindings
            from the local client's config while plugin actions run on the
            server. The reviewr binding is set even where the plugin itself is
            disabled, so it still works from a client attached to a remote host.
          '';
        };

        reviewr.enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to link the reviewr plugin (a diff review pane beside the
            agent chat) into herdr. herdr keeps its plugin registry in
            ~/.config/herdr/plugins.json, which it also writes itself, so the
            plugin is registered with `herdr plugin link` on activation rather
            than by managing that file.
          '';
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        environment.systemPackages = [ pkgs.herdr ];

        dev.claudecode.enable = mkDefault true;

        home-manager.users."${user}" = {
          xdg.configFile."herdr/config.toml".source =
            tomlFormat.generate "herdr-config.toml" cfg.settings;
        };
      })

      (mkIf (cfg.enable && cfg.reviewr.enable) {
        # The store path stays alive because this script references it.
        # `plugin link` replaces any entry with the same id, including one from
        # `herdr plugin install`. `plugin unlink` needs a running server, so
        # disabling this leaves the last link in place.
        home-manager.users."${user}" = { lib, ... }: {
          home.activation.herdrReviewr =
            lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              registry="$HOME/.config/herdr/plugins.json"
              if ! ${pkgs.jq}/bin/jq -e --arg root ${reviewr} \
                   'any(.[]; .plugin_id == "persiyanov.reviewr" and .plugin_root == $root)' \
                   "$registry" >/dev/null 2>&1; then
                $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr plugin link ${reviewr} >/dev/null
                $VERBOSE_ECHO "herdr: linked reviewr ${reviewr.version}"
              fi
            '';
        };
      })
    ];
  }
