{ config, lib, pkgs, ... }:

let
  sources = import ../../npins/default.nix;
  stylix = import sources.stylix;
in
{
  imports =
    [ ./hardware-configuration.nix
      ../../modules
      ../../common.nix
      ../../packages.nix
      ../../desktop.nix
      "${sources.home-manager}/nixos/default.nix"
      ./home.nix
      stylix.nixosModules.stylix
    ];

  attributes.machine.name = "woody";
  attributes.mainUser = {
    name = "aru";
    fullName = "Atle Rudshaug";
    email = "atle.rudshaug@gmail.com";
  };

  ext.nix.core.permittedInsecurePackages = [
    "openssl-1.1.1w"
  ];

  appearance.stylix.enable = true;

  ext.networking = {
    core = {
      enable = true;
      hostId = "007f0200";
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

  wm.i3.enable = true;

  ext.virtualization = {
    core.enable = true;
    docker.core.enable = true;
  };

  dev = {
    direnv.enable = true;
    git.core.enable = true;
    ide = {
      rider.enable = true;
      vscode.enable = true;
    };
    dotnet.enable = true;
  };

  # Bootloader
  boot = {
    loader = {
#      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      grub = {
        enable = true;
        #        device = "/dev/sda";
        devices = [ "nodev" ];
        efiSupport = true;
        useOSProber = true;
      };

#      tmp.cleanOnBoot = true;
    };
  };

  # Enable networking
  networking = {
    hostName = "woody"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  };

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = false;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };

  # List services that you want to enable:

  # Security
  #security.pam.services.gdm.enableGnomeKeyring = true;
  #services.gnome.gnome-keyring.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
