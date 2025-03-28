{ config, lib, pkgs, ...}:

let
  cfg = config.appearance.stylix;
  user = config.attributes.mainUser.name;
in
  {
    options.appearance.stylix = { enable = lib.mkEnableOption "stylix"; };

    config = lib.mkIf cfg.enable {
      home-manager.users."${user}".stylix = {
        enable = true;
        autoEnable = true;
        targets.rofi.enable = false;
      };

      stylix = {
        enable = true;
        autoEnable = true;

        base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
        # base16Scheme = {
        #   base00 = "242424"; # ----
        #   base01 = "3c3836"; # ---
        #   base02 = "504945"; # --
        #   base03 = "665c54"; # -
        #   base04 = "bdae93"; # +
        #   base05 = "d5c4a1"; # ++
        #   base06 = "ebdbb2"; # +++
        #   base07 = "fbf1c7"; # ++++
        #   base08 = "fb4934"; # red
        #   base09 = "fe8019"; # orange
        #   base0A = "fabd2f"; # yellow
        #   base0B = "b8bb26"; # green
        #   base0C = "8ec07c"; # aqua/cyan
        #   base0D = "7daea3"; # blue
        #   base0E = "e089a1"; # purple
        #   base0F = "f28534"; # brown
        # };

        image = ./wp11058332-gruvbox-wallpapers.png;

        fonts = {
          monospace = {
            package = pkgs.nerd-fonts.jetbrains-mono;
            name = "JetBrainsMono Nerd Font Mono";
          };
          sansSerif = {
            package = pkgs.dejavu_fonts;
            name = "DejaVu Sans";
          };
          serif = {
            package = pkgs.dejavu_fonts;
            name = "DejaVu Serif";
          };

          sizes = {
            applications = 12;
            terminal = 12;
            desktop = 10;
            popups = 10;
          };
        };

        opacity = {
          applications = 1.0;
          terminal = 1.0;
          desktop = 1.0;
          popups = 1.0;
        };
      };
    };
  }
