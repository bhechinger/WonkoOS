{
  autoPatchelfHook ? null,
  fetchurl,
  lib,
  libgcc ? null,
  stdenv,
}:

let
  assets = {
    x86_64-linux = {
      name = "linux-x86_64";
      hash = "sha256-BdPOTsCrUah2vv2JtkPD5/LVSJvgOYo4zvb7Og0lf8E=";
    };
    aarch64-darwin = {
      name = "macos-arm64";
      hash = "sha256-fDuPrb5ZBIahksc02MPTjM4OTaHwKUDmrDBsGtpn8XE=";
    };
  };
  asset = assets.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "omnigraph";
  version = "0.10.0";

  src = fetchurl {
    url = "https://github.com/ModernRelay/omnigraph/releases/download/v0.10.0/omnigraph-${asset.name}.tar.gz";
    inherit (asset) hash;
  };

  nativeBuildInputs = lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook;
  buildInputs = lib.optional stdenv.hostPlatform.isLinux libgcc;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    tar -xzf "$src"
    install -m 0755 omnigraph omnigraph-server "$out/bin/"
    runHook postInstall
  '';

  meta = {
    description = "Lakehouse-native graph database with Git-style workflows";
    homepage = "https://www.omnigraph.dev";
    license = lib.licenses.mit;
    mainProgram = "omnigraph";
    platforms = builtins.attrNames assets;
  };
}
