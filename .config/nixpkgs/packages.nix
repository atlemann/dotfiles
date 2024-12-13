{ pkgs, ... }:

let

  my_dotnet = with pkgs.dotnetCorePackages; (combinePackages [
    sdk_6_0
    runtime_6_0
    sdk_7_0
    runtime_7_0
    sdk_8_0
    runtime_8_0
  ]);

  my_emacs = import ./emacs.nix { inherit pkgs; };

  in {
    # Gnome apps require dconf to remember default settings
    programs.dconf.enable = true;

    # Allow testing .NET compiled executables
    programs.nix-ld.enable = true;

    # Make sure dotnet finds the correct binaries
    environment.variables = {
      DOTNET_ROOT = my_dotnet;
    };

    environment.systemPackages = with pkgs; [
      alacritty
      autorandr
      aws-workspaces
      azure-cli
      bottom
      curl
      dconf
      direnv
      gcc
      git
      htop
      kubectl
      kubelogin
      lsd
      my_dotnet
      my_emacs
      nodePackages.typescript-language-server
      ntfs3g
      nixos-option
      nodejs_20
      npins
      pciutils
      pqrs
      pyright
      python3
      ripgrep
      semgrep
      udiskie
      udisks
      csharp-ls
      (fsautocomplete.overrideDerivation (o: { dotnet-runtime = my_dotnet; }))
      usbutils
      yarn

      # Rust packages
      # (fenix.complete.withComponents [
      #   "cargo"
      #   "clippy"
      #   "rust-src"
      #   "rustc"
      #   "rustfmt"
      # ])

      rustc
      rustup
      rust-analyzer

      # NixOS helpers
      (writeShellScriptBin "nixos-switch" (builtins.readFile ./nixos-switch.sh))
    ];
  }
