{ config, lib, pkgs, ... }:

let
  theme = import ./theme.nix;
in
  {
  home-manager.users.aru = {

    programs.feh.enable = true;

    programs.vscode = {
      enable = true;
      mutableExtensionsDir = false;
      extensions = with pkgs.vscode-extensions; [
        eamodio.gitlens
        humao.rest-client
        ionide.ionide-fsharp
        jdinhlife.gruvbox
        mhutchie.git-graph
        ms-dotnettools.csharp
        ms-dotnettools.vscode-dotnet-runtime
        ms-vscode-remote.remote-ssh
      ];
      userSettings = {
        "notebook.lineNumbers" = "on";
        "files.autoSave" = "afterDelay";

        # Fonts
        "editor.fontLigatures" = true;

        # Whitespace
        "editor.renderWhitespace" = "all";
        "files.trimTrailingWhitespace" = true;
        "files.trimFinalNewlines" = true;
        "files.insertFinalNewline" = true;

        # F#
        "FSharp.inlayHints.typeAnnotations" = false;
        "FSharp.inlayHints.parameterNames" = false;
        "FSharp.inlayHints.enabled" = false;
      };
    };
  };
}
