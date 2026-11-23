{ config, lib, pkgs, ... }:

let
  sources = import ../../npins/default.nix;
  stylix = import sources.stylix;
in
{
  # Headless: cherry-pick only the modules we need, a server has no use for
  # the desktop modules.
  imports =
    [ ./hardware-configuration.nix
      "${sources.home-manager}/nixos/default.nix"

      ../../modules/attributes.nix
      ../../modules/user.nix
      ../../modules/home-manager.nix

      ../../modules/nix/core
      ../../modules/networking/ssh
      ../../modules/networking/tailscale
      # TODO: never committed, copy from the old elisha SSD
      # ../../modules/networking/ntfy
      ../../modules/shell/core
      ../../modules/shell/bash
      ../../modules/shell/tmux
      ../../modules/shell/starship
      ../../modules/shell/tools
      ../../modules/dev/git
      ../../modules/dev/dotnet
      ../../modules/dev/claudecode
      ../../modules/dev/python
      ../../modules/dev/rust
      # TODO: never committed, copy from the old elisha SSD
      # ../../modules/dev/playwright
      ../../modules/emacs
    ];

  # Stylix stays disabled, but modules/home-manager.nix shares every hm.nix,
  # and appearance/stylix/hm.nix needs the stylix options to exist.
  home-manager.sharedModules = [ stylix.homeModules.stylix ];

  attributes.machine.name = "elisha";
  attributes.mainUser = {
    name = "aru";
    fullName = "Atle Rudshaug";
    email = "atle.rudshaug@gmail.com";
  };

  # Headless server: enable only the modules useful without a display.
  ext.networking = {
    ssh = {
      enable = true;
      X11Forwarding = true;
    };
    tailscale.enable = true;
    # ntfy = {
    #   enable = true;
    #   baseUrl = "http://elisha.piranha-grouse.ts.net";
    # };
  };

  shell = {
    core.enable = true;
    tools.enable = true;
    bash.enable = true;
    tmux.enable = true;
    prompts.starship.enable = true;
  };

  dev = {
    git.enable = true;
    dotnet.enable = true;
    python.enable = true;
    rust.enable = true;
    claudecode.enable = true;
    # playwright.enable = true;
  };

  emacs.enable = true;

  # Bootloader
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = "/boot";
    };
    supportedFilesystems = [ "zfs" ];
    zfs = {
      extraPools = [ "zfspool" ];
      # Root is ext4, only the data pool is ZFS
      forceImportRoot = false;
    };

    # Prevent the kernel's hid-generic from binding to the CyberPower UPS:
    # it claims the HID interface at enumeration and then races NUT's
    # libusb auto-detach, causing usbhid-ups's Report descriptor read to
    # fail with EPIPE/EAGAIN ("No matching HID UPS found"). With
    # HID_QUIRK_IGNORE (0x4) the kernel leaves the device alone and
    # usbhid-ups can claim it cleanly.
    extraModprobeConfig = ''
      options usbhid quirks=0x0764:0x0501:0x00000004
    '';
  };

  # Networking: keep direct config on this headless box (no NetworkManager).
  networking = {
    hostName = "elisha";
    hostId = "171f21ca";
    firewall = {
      enable = true;
      allowPing = true;
      allowedTCPPorts = [ 5173 ];
    };
  };

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [ stdenv.cc.cc.lib zlib ];

  # Server-specific packages (no desktop.nix / top-level packages.nix imported).
  environment.systemPackages = with pkgs; [
    jotta-cli
    nut
    ntfs3g
  ];

  # Jottacloud backup daemon as a user service.
  users.users.aru.linger = true;

  systemd.user.services.jottad = {
    description = "Jottad backup daemon";
    wantedBy = [ "default.target" ];
    after = [ "network.target" ];

    unitConfig = {
      StartLimitBurst = 5;
      StartLimitIntervalSec = 60;
    };

    serviceConfig = {
      ExecStart = "${pkgs.jotta-cli}/bin/jottad";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # jotta-cli installs its own unit at ~/.config/systemd/user/jottad.service pointing into
  # the store. That path outranks /etc/systemd/user, so once the store path is GC'd the unit
  # goes "not-found" and backups silently stop. Keep the path clear; the unit above is the
  # only one that should exist.
  systemd.tmpfiles.rules = [
    "r /home/aru/.config/systemd/user/jottad.service"
  ];

  # Network shares
  services = {
    nfs.server.enable = true;

    samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          security = "user";
          "server string" = "elisha";
          "netbios name" = "elisha";
          "hosts allow" = "192.168.1. 127.0.0.1 localhost";
          "hosts deny" = "0.0.0.0/0";
          "guest account" = "nobody";
          "map to guest" = "bad user";
        };
        bilder = {
          path = "/mnt/data/bilder";
          "read only" = "no";
          browseable = "yes";
          writable = "yes";
          "guest ok" = "yes";
          "create mask" = "0644";
          "directory mask" = "0755";
          "valid users" = "aru, atle";
          "force user" = "aru";
        };
        backup = {
          path = "/mnt/data/backup";
          "read only" = "no";
          browseable = "yes";
          writable = "yes";
          "guest ok" = "no";
          "create mask" = "0644";
          "directory mask" = "0755";
          "valid users" = "aru";
          "force user" = "aru";
        };
      };
    };

    samba-wsdd = {
      enable = true;
      openFirewall = true;
      hostname = "elisha";
    };
  };

  # UPS monitoring
  power.ups = {
    enable = true;

    ups."cyberpower" = {
      driver = "usbhid-ups";
      port = "auto";
      description = "DX800E-DE";
      directives = [
        "vendorid = 0764"
        "productid = 0501"
      ];
    };

    upsd = {
      listen = [
        {
          address = "localhost";
          port = 3493;
        }
      ];
    };

    users = {
      monuser = {
        passwordFile = "/home/aru/nutpasswd.txt";
        upsmon = "primary";
        actions = [ "set" "fsd" ];
        instcmds = [ "all" ];
      };
    };

    upsmon.monitor."cyberpower" = {
      user = "monuser";
      system = "cyberpower@localhost:3493";
      powerValue = 1;
    };
  };

  system.stateVersion = "24.05"; # Did you read the comment?
}
