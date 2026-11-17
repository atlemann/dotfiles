{ config, lib, ... }:
with lib;

let
  cfg = config.shell.vt.alacritty;
in
  {
    options = {
      shell.vt.alacritty = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable Alacritty.";
        };
      };
    };

    config = mkIf cfg.enable {
      programs.alacritty = {
        enable = true;
        settings = {
          env = {
            LESS = "-SRXF";
            TERM = "xterm-256color";
          };
          window = {
            padding = {
              x = 2;
              y = 2;
            };
            decorations = "full";
            dynamic_title = true;
          };
           bell = {
            animation = "EaseOutExpo";
            duration = 0;
          };
          selection = { semantic_escape_chars = '',│`|:"' ()[]{}<>''; };
          cursor = { style = "Beam"; };
        };
      };
    };
  }
