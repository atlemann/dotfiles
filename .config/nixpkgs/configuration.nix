# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, lib, pkgs, ... }:

let
  sources = import ./npins/default.nix;
  unstable = import sources.unstable { config.allowUnfree = true; };

  combinePackagesCopy = sdks: pkgs.runCommand "dotnet-core-combined" {} ''
    mkdir $out
    for sdk in ${toString sdks}; do
        cp --no-preserve=mode -r $sdk/. $out
    done
    chmod -R +x $out/dotnet
  '';

  my_dotnet = with unstable; (combinePackagesCopy (with dotnetCorePackages; [
    sdk_6_0
    sdk_7_0
    sdk_8_0
  ]));

  my_emacs = import ./emacs.nix { inherit pkgs; };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      "${sources.home-manager}/nixos/default.nix"
      ./home.nix
    ];

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
      trusted-users = [ "aru" ];
      max-jobs = "auto";
    };
  };

  # Bootloader.
  boot = {
    loader = {
      grub = {
        enable = true;
        device = "/dev/sda";
        useOSProber = true;
      };

#      tmp.cleanOnBoot = true;
    };

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
    hostName = "aru-ws"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
  };

  services = {
    tailscale.enable = true;
    tailscale.package = unstable.tailscale;

    devmon.enable = true;
    gvfs.enable = true;
    udisks2.enable = true;

    picom = {
      enable = true;
      vSync = true;
      backend = "xrender"; #"glx";
    };

    # Configure keymap in X11
    xserver.xkb = {
      layout = "us";
      variant = "";
    };

    # Enable CUPS to print documents.
    printing.enable = true;

    # Enable the X11 windowing system.
    xserver = {
      enable = true;
      displayManager = {
        lightdm.enable = true;
        setupCommands = ''
          LEFT='DP-6'
          RIGHT='DP-4'
          ${pkgs.xorg.xrandr}/bin/xrandr --output $LEFT --primary --auto --output $RIGHT --auto --right-of $LEFT --rotate left
        '';
      };
      windowManager.i3.enable = true;
      videoDrivers = ["nvidia"];
    };
  };

  # Graphics
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

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

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    alacritty
    autorandr
    aws-workspaces
    azure-cli
    bottom
    chromium
    curl
    dconf
    direnv
    dunst
    feh
    flameshot
    gcc
    git
    gnome.nautilus
    htop
    i3status-rust
    kdiff3
    kubectl
    kubelogin
    lsd
    my_dotnet
    my_emacs
    nodePackages.typescript-language-server
    nixos-option
    nodejs_20
    npins
    pavucontrol
    pciutils
    pqrs
    pulseaudio
    pyright
    python3
    ripgrep
    rofi
    semgrep
    simplescreenrecorder
    slack
    spotify
    udiskie
    udisks
    unstable.calibre
    unstable.csharp-ls
    (unstable.fsautocomplete.overrideDerivation (o: { dotnet-runtime = my_dotnet; }))
    # realpath `which copilot-agent` and symlink in ~/.local/share/JetBrains/Rider2023.1/github-copilot-intellij/copilot-agent/bin
    unstable.github-copilot-intellij-agent
    unstable.jetbrains.rider
    unstable.vivaldi
    usbutils
    vmware-horizon-client
    vscode
    workrave
    yarn

    # Rust packages
    (fenix.complete.withComponents [
      "cargo"
      "clippy"
      "rust-src"
      "rustc"
      "rustfmt"
    ])
    unstable.rust-analyzer

    # NixOS helpers
    (writeShellScriptBin "nixos-switch" (builtins.readFile ./nixos-switch.sh))
  ];

  environment = {
    variables = {
      #     MONITOR_PRIMARY = "eDP-1";
      DOTNET_ROOT = my_dotnet;
#      EDITOR = "emacs";
    };
  };

  # Allow testing .NET compiled executables
  programs.nix-ld.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # List services that you want to enable:

  # Security
  #security.pam.services.gdm.enableGnomeKeyring = true;
  #services.gnome.gnome-keyring.enable = true;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
