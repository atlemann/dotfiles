{ pkgs, unstable, ... }:

let
  combinePackagesCopy = sdks: pkgs.runCommand "dotnet-core-combined" {} ''
    mkdir $out
    for sdk in ${toString sdks}; do
        cp --no-preserve=mode -r $sdk/. $out
    done
    chmod -R +x $out/dotnet
  '';

  my_dotnet = with unstable; (combinePackagesCopy (with dotnetCorePackages; [
    sdk_6_0
    sdk_8_0
    runtime_6_0
    runtime_8_0
  ]));

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
  }
