{ stdenvNoCC, fetchFromGitHub, fetchurl }:

# The plugin checkout with the prebuilt release binary in bin/, where its pane
# command looks for it. This is what the plugin's own install.sh produces on
# `herdr plugin install`, which nix can't run since it downloads at build time.
stdenvNoCC.mkDerivation rec {
  pname = "herdr-reviewr";
  version = "0.39.0";

  src = fetchFromGitHub {
    owner = "persiyanov";
    repo = "herdr-reviewr";
    rev = "v${version}";
    hash = "sha256-QD+hqFt1zpzGiJELJwwyJy4s6ASbIdOYnsw2S1qIaHs=";
  };

  # Statically linked (musl), so it needs no patchelf.
  binary = fetchurl {
    url = "https://github.com/persiyanov/herdr-reviewr/releases/download/v${version}/herdr-reviewr-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-lGPrpBz5YvaAUR24CQnX5GojZARbLHbL/+gDfINXKPQ=";
  };

  dontBuild = true;

  installPhase = ''
    cp -r . $out
    mkdir -p $out/bin
    tar -xzf ${binary} -C $out/bin
  '';

  meta.platforms = [ "x86_64-linux" ];
}
