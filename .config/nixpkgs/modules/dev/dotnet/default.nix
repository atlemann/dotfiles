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

        # Make sure dotnet finds the correct binaries
        environment.variables = {
          DOTNET_ROOT = "${my_dotnet}/share/dotnet";
        };

        environment.systemPackages = with pkgs; [
            csharp-ls
            fantomas
            fsautocomplete
            my_dotnet
            netcoredbg
        ];

        home-manager.users."${user}" = {
          home.sessionPath = [ "$HOME/.dotnet/tools" ];

          # Inject Emacs Lisp that has to hold Nix store paths; anything
          # portable belongs in configuration.org instead.
          programs.emacs.extraConfig = ''
            ;; Pin fsharp-ts-eglot to the Nix-built fsautocomplete so the LSP
            ;; server tracks this derivation rather than whatever happens to be
            ;; in /run/current-system/sw/bin/ or ~/.emacs.d at runtime.
            (with-eval-after-load 'fsharp-ts-eglot
              (setq fsharp-ts-eglot-server-install-dir "${pkgs.fsautocomplete}/bin/"
                    fsharp-ts-eglot-auto-install nil))

            ;; Same idea for dap-mode's .NET debugger.
            (with-eval-after-load 'dap-netcore
              (setq dap-netcore-install-dir "${pkgs.netcoredbg}/bin")
              (setq dap-netcore-download-url nil))
          '';
        };
      })
    ];
  }
