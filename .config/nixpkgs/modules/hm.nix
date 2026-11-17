# The home-manager halves of the modules in ./default.nix, in the same order.
# NixOS hosts get these through home-manager.sharedModules (./home-manager.nix)
# and turn them on from the matching NixOS options. Hosts where NixOS is
# managed elsewhere, like hosts/devbox, import this file directly.
{
  imports = [
    ./attributes.nix

    ./appearance/stylix/hm.nix
    ./dev/cloud/hm.nix
    ./dev/direnv/hm.nix
    ./dev/dotnet/hm.nix
    ./dev/python/hm.nix
    ./dev/rust/hm.nix
    ./dev/git/hm.nix
    ./dev/git/forges/hm.nix
    ./dev/herdr/hm.nix
    ./emacs/hm.nix
    ./networking/ssh/hm.nix
    ./shell/alacritty/hm.nix
    ./shell/bash/hm.nix
    ./shell/core/hm.nix
    ./shell/starship/hm.nix
    ./shell/tmux/hm.nix
    ./shell/tools/hm.nix
  ];
}
