#!/bin/bash
# Install nix
# sh < (curl -L https://nixos.org/nix/install) --daemon

# If curl isn't installed
wget https://nixos.org/nix/install
chmod +x install
./install --daemon

# Add extra channels
nix-channel --add https://github.com/nix-community/home-manager/archive/release-22.05.tar.gz home-manager
nix-channel --update

export NIX_PATH=$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels${NIX_PATH:+:$NIX_PATH}

nix-shell '<home-manager>' -A install

# Remove default home-manager config, since we're replacing it with our own
mv .config/nixpkgs/home.nix .config/nixpkgs/home_bakup.nix

# Clone dotfiles repo
nix-shell -p git --run "git clone git@github.com:atlemann/dotfiles.git .dotfiles"

# Use Stow to symlink dotfiles to correct locations
pushd .dotfiles
nix-shell -p stow --run "stow ."
popd

# NOTE: Might have to comment out statusComman=i3status-rs with pointer to toml file.
# For some reason that is evaluated before i3status-rs is enabled.

home-manager switch

sudo cat > /usr/share/xsessions/i3.desktop <<EOF
[Desktop Entry]
Name=i3
Comment=improved dynamic tiling window manager
Exec=i3
TryExec=i3
Type=Application
X-LightDM-DesktopName=i3
DesktopNames=i3
Keywords=tiling;wm;windowmanager;window;manager;
EOF
