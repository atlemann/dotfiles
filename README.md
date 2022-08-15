# dotfiles

## Stuff needed

- Libfuse2 is to run JetBrains toolbox

sudo apt install curl fonts-firacode git dotnet-sdk-6.0 libfuse2

git config --global user.name "Atle Rudshaug"
git config --global user.email "atle.rudshaug@gmail.com"

mkdir src
pushd src
git clonegit@github.com:atlemann/installscripts.git
./installscripts/setup.git.sh
popd

git clone git@github.com:atlemann/dotfiles.git .dotfiles
pushd .dotfiles
stow .
popd

sudo snap install emacs --classic
sudo snap install code --classic

code --install-extension Ionide.ionide-fsharp
code --install-extension ms-dotnettools.csharp
code --install-extension mhutchie.git-graph

curl -fsSL https://tailscale.com/install.sh | sh

### Add this to VSCode settings.json

    "editor.fontLigatures": true,
    "editor.fontFamily": "Fira Code",
    "editor.fontSize": 14,
