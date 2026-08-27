{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.shell.tmux;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      shell.tmux = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable tmux terminal multiplexer";
        };
      };
    };

    config = mkIf cfg.enable {
      home-manager.users."${user}" = {
        programs.tmux = {
          enable = true;
          terminal = "tmux-256color";
          historyLimit = 10000;
          keyMode = "vi";
#          prefix = "C-a";
          escapeTime = 0;
          mouse = true;
          baseIndex = 1;
          plugins = with pkgs.tmuxPlugins; [
            {
              plugin = resurrect;
              extraConfig = ''
                set -g @resurrect-capture-pane-contents 'on'

                # Every entry uses `->` to rewrite the restored command.
                # emacs and nit run as full /nix/store paths, which the
                # built-in matcher never matches (it anchors at the start of
                # the command), and restoring them verbatim would pin a stale
                # store path. claude is restarted with --continue so the pane
                # picks up its last conversation instead of an empty session.
                set -g @resurrect-processes '"~claude->claude --continue" "~bin/emacs->emacs -nw ." "~bin/nit serve->nit serve"'
              '';
            }
            {
              plugin = continuum;
              extraConfig = ''
                set -g @continuum-restore 'on'
                set -g @continuum-save-interval '15'
              '';
            }
          ];
          extraConfig = ''
            set -ga terminal-overrides ",*256col*:Tc"

            # Split panes with | and -
            bind | split-window -h -c "#{pane_current_path}"
            bind - split-window -v -c "#{pane_current_path}"
            unbind '"'
            unbind %

            # New window keeps current path
            bind c new-window -c "#{pane_current_path}"

            # Vim-style pane navigation
            bind h select-pane -L
            bind j select-pane -D
            bind k select-pane -U
            bind l select-pane -R

            # Reload config
            bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded"

            # Status bar
            set -g status-position top
          '';
        };
      };
    };
  }
