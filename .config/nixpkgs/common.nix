{ config, lib, pkgs, sources, unstable, ... }:

  let
    in
    {
      documentation.enable = false;

      # Configure the Nix package manager
      nixpkgs = {
        overlays = [
          (import sources.emacs-overlay)
          (import "${fetchTarball "https://github.com/nix-community/fenix/archive/main.tar.gz"}/overlay.nix")
        ];
        pkgs = import sources.nixos {
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [
              "openssl-1.1.1w"
              "openssl-1.1.1m"
            ];
          };
        };
      };

      nix = {
        #    package = pkgs.nix_2_3;
        nixPath = ["nixpkgs=${sources.nixos}:nixos-config=/etc/nixos/configuration.nix"];
        settings = {
          max-jobs = "auto";
        };
      };

      boot = {
        # This is required for dotnet to run correctly
        kernel.sysctl."fs.inotify.max_user_instances" = 524288;
      };

      # Set your time zone.
      time.timeZone = "Europe/Oslo";

      # Select internationalisation properties.
      i18n.defaultLocale = "en_US.UTF-8";

      # Enable docker
      virtualisation = {
        docker.enable = true;
        # virtualbox.host.enable = true;
        # this is needed to get a bridge with DHCP enabled
        libvirtd.enable = true;
      };

      # Enable networking
      networking = {
        networkmanager.enable = true;
      };

      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
      };

      services = {
        tailscale.enable = true;
        tailscale.package = unstable.tailscale;

        # Enable the OpenSSH daemon.
        openssh.enable = true;

        # Support removable drives and such
        devmon.enable = true;
        gvfs.enable = true;
        udisks2.enable = true;
      };

      console = {
        keyMap = "us";
      };

      fonts = {
        fontconfig = {
          enable = true;
          antialias = true;
        };
        packages = with pkgs; [
          emacs-all-the-icons-fonts
          nerdfonts
          font-awesome
          jetbrains-mono
        ];
      };

      # Graphics for alacritty
      hardware.opengl = {
        enable = true;
        driSupport = true;
        driSupport32Bit = true;
      };
    }
