{ config, lib, pkgs, ... }:

let
  sources = import ../../npins/default.nix;
  stylix = import sources.stylix;
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../modules
      ../../packages.nix
      ../../desktop.nix
      "${sources.home-manager}/nixos/default.nix"
      ./home.nix
      stylix.nixosModules.stylix
    ];

  attributes.machine.name = "aru-ws";
  attributes.mainUser = {
    name = "aru";
    fullName = "Atle Rudshaug";
    email = "atle.rudshaug@gmail.com";
  };

  ext.nix.core.permittedInsecurePackages = [
    "openssl-1.1.1w"
  ];

  appearance = {
    stylix.enable = true;
    fonts = {
      enable = true;
      antialias = true;
    };
  };

  ext.networking = {
    core = {
      enable = true;
      hostId = "dd215df2";
    };
    ssh = {
      enable = true;
      X11Forwarding = true;
    };
    tailscale.enable = true;
    wireless = {
      enable = true;
      bluetooth.enable = true;
      wm.enable = true;
    };
  };

  shell = {
    core = {
      enable = true;
      dev.enable = true;
    };
    tools.enable = true;
    bash.enable = true;
    vt.alacritty.enable = true;
    prompts.starship.enable = true;
  };

  workstation = {
    sound.enable = true;
    rofi.enable = true;
    flameshot.enable = true;
    dunst.enable = true;
    drives.enable = true;
    video.opengl.enable = true;
  };

  emacs.enable = true;

  wm.i3.enable = true;

  ext.virtualization = {
    core.enable = true;
    docker.core.enable = true;
  };

  dev = {
    cloud.enable = true;
    direnv.enable = true;
    git.core.enable = true;
    ide = {
      rider.enable = true;
      vscode.enable = true;
    };
    dotnet.enable = true;
  };

  browsers.enable = true;

  # Bootloader
  boot = {
    loader = {
      grub = {
        enable = true;
        device = "/dev/sda";
        useOSProber = true;
      };
    };
  };

  services.xserver = {
    displayManager = {
      setupCommands = ''
        LEFT='DP-6'
        RIGHT='DP-4'
        ${pkgs.xorg.xrandr}/bin/xrandr --output $LEFT --primary --auto --output $RIGHT --right-of $LEFT --rotate left
      '';
    };
    videoDrivers = ["nvidia"];
  };

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = false;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Enable password auth
  services.openssh = {
    settings = {
      PasswordAuthentication = true;
    };
  };

  networking.firewall = {
    enable = false;
    allowedTCPPorts = [ 22 5000 ];
  };

  fileSystems."/mnt/internal" = {
    device = "jackson.resoptima.local:/mnt/bigstorage/internal";
    fsType = "nfs";
    options = ["x-systemd.automount" "noauto"];
  };

  fileSystems."/mnt/external" = {
    device = "jackson.resoptima.local:/mnt/bigstorage/external";
    fsType = "nfs";
    options = ["x-systemd.automount" "noauto"];
  };

  fileSystems."/mnt/data" = {
    device = "jackson.resoptima.local:/mnt/bigstorage/data";
    fsType = "nfs";
    options = ["x-systemd.automount" "noauto"];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
