{ config, lib, pkgs, ... }:

  let
    sources = import ./npins/default.nix;
  in
    {
      documentation.enable = false;

      # Configure the Nix package manager
      nixpkgs = {
        overlays = [
          (import sources.emacs-overlay)
          (import "${fetchTarball "https://github.com/nix-community/fenix/archive/main.tar.gz"}/overlay.nix")
        ];
        pkgs = import sources.nixpkgs {
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [
              "openssl-1.1.1w"
              "openssl-1.1.1m"
              "dotnet-core-combined"
              "dotnet-sdk-wrapped-6.0.428"
              "dotnet-sdk-6.0.428"
              "dotnet-runtime-wrapped-6.0.36"
              "dotnet-runtime-6.0.36"
              "dotnet-sdk-wrapped-7.0.410"
              "dotnet-sdk-7.0.410"
              "dotnet-runtime-wrapped-7.0.20"
              "dotnet-runtime-7.0.20"
            ];
          };
        };
      };

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users.aru = {
        isNormalUser = true;
        description = "Atle Rudshaug";
        extraGroups = [
          "wheel"
          "networkmanager"
          "libvirtd"
          "docker"
        ];
        packages = with pkgs; [];
      };

      nix = {
        #    package = pkgs.nix_2_3;
        nixPath = ["nixpkgs=${sources.nixpkgs}:nixos-config=/etc/nixos/configuration.nix"];
        settings = {
          trusted-users = [ "aru" ];
          max-jobs = "auto";
          netrc-file = "/etc/nix/netrc";
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
          nerd-fonts.jetbrains-mono
          font-awesome
          jetbrains-mono
        ];
      };
    }
