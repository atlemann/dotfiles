{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.keyring;
  user = config.attributes.mainUser.name;
in
  {
    options = {
      workstation.keyring = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable GNOME Keyring for secret storage.";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        # System packages for libsecret (needed by many apps)
        environment.systemPackages = with pkgs; [ libsecret ];

        # Enable gnome-keyring system service
        services.gnome.gnome-keyring.enable = true;

        # PAM integration: unlock keyring on login
        security.pam.services.login.enableGnomeKeyring = true;

        # Optional: Seahorse for GUI keyring management
        home-manager.users."${user}" = {
          home.packages = [ pkgs.seahorse ];
        };
      })
    ];
  }
