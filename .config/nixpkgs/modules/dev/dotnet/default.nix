{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.dotnet;
  user = config.attributes.mainUser.name;

  # Combine SDKs
  my_dotnet = with pkgs.dotnetCorePackages; (combinePackages [
    sdk_8_0
    runtime_8_0
    sdk_9_0
    runtime_9_0
    sdk_10_0
    runtime_10_0
  ]);

  # The fsautocomplete apphost links this nixpkgs' OpenSSL, but its wrapper
  # runs it on whichever dotnet is on PATH. A project dotnet from another
  # nixpkgs loads a second OpenSSL and the runtime aborts, so pin the runtime.
  my_fsautocomplete = pkgs.writeShellScriptBin "fsautocomplete" ''
    export DOTNET_ROOT=${my_dotnet}/share/dotnet
    export LD_LIBRARY_PATH=${pkgs.icu}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    exec ${pkgs.fsautocomplete}/lib/fsautocomplete/fsautocomplete "$@"
  '';
in
  {
    options = {
      dev.dotnet = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install .NET tools";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        # Allow testing .NET compiled executables
        programs.nix-ld.enable = true;

        # Make sure dotnet finds the correct binaries
        environment.variables = {
          DOTNET_ROOT = "${my_dotnet}/share/dotnet";
        };

        environment.systemPackages = with pkgs; [
            csharp-ls
            fantomas
            my_fsautocomplete
            my_dotnet
            netcoredbg
        ];

        home-manager.users."${user}" = {
          home.sessionPath = [ "$HOME/.dotnet/tools" ];

          # Inject Emacs Lisp that has to hold Nix store paths; anything
          # portable belongs in configuration.org instead.
          programs.emacs.extraConfig = ''
            ;; Resolve fsautocomplete from the buffer's exec-path, so a project
            ;; dev shell (via envrc) supplies one built against its own dotnet.
            ;; Elsewhere this falls back to the pinned one in systemPackages.
            (with-eval-after-load 'fsharp-ts-eglot
              (setq fsharp-ts-eglot-server-install-dir nil
                    fsharp-ts-eglot-auto-install nil))
          '';
        };
      })
    ];
  }
