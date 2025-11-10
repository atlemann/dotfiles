{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.shell.tools;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      shell.tools = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Add extra shell tools";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        home-manager.users."${user}" = {
          home.packages = with pkgs; [
            broot       # A better way to navigate directories, with a tree view and fuzzy searching
            dysk        # Prefviously lfs, utility for listing your filesystems
            gron        # Flattens JSON into a series of assignments, making it easier to work with using grep and awk.
            jc          # Converts various command outputs into JSON format.
            jless       # A JSON viewer with a user-friendly interface.
            jp          # A command-line tool for parsing and querying JSON (similar to jq but different).
            jqp         # JSON processor that can be used for querying JSON data
            miller      # A powerful tool for processing CSV, TSV, and other structured data formats.
            pipe-rename # A tool for renaming files using a pipeline-based approach.
            ripgrep-all # Extensions over rg to search PDF's, archives etc.
            sad         # A search-and-replace tool that can apply transformations interactively.
            sd          # A simpler and faster alternative to sed for replacing text.
            pqrs
            pciutils
            nixos-option
            curl
            ripgrep
          ];
          programs = {
            bottom.enable = true;
            htop.enable = true;
            # This should have been added to HM, but not in my source yet
            # ripgrep-all = {
            #   enable = true;
            # };
            lsd = {
              enable = true;
              enableBashIntegration = true;
              settings = {
                classic = false;
                blocks = [
                  "permission"
                  "user"
                  "group"
                  "size"
                  "date"
                  "name"
                ];
                color = {
                  when = "auto";
                };
                date = "+%a %Y %b %d %X";
                dereference = true;
                hyperlink = "always";
                icons = {
                  when = "auto";
                  theme = "fancy";
                  separator = " ";
                };
                layout = "grid";
                size = "default";
                sorting = {
                  column = "name";
                  reverse = false;
                  dir-grouping = "first";
                };
                no-symlink = false;
                symlink-arrow = "⇒";
              };
            };
            bat = {
              enable = true;
            };
            jq = {
              enable = true;
              colors = {
                null       = "1;35";  # base0E → purple
                false      = "1;31";  # base08 → red
                true       = "1;31";  # base08 → red
                numbers    = "1;36";  # base0C → aqua
                strings    = "1;33";  # base0A → yellow
                arrays     = "1;32";  # base0B → green
                objects    = "1;34";  # base0D → blue
                objectKeys = "0;33";  # base09 → orange (non-bold yellow)
              };
            };
          };
        };
      })
    ];
  }
