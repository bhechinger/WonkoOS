{
  autoPatchelfHook,
  fetchurl,
  lib,
  libgcc,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "omnigraph";
  version = "0.10.0";

  src = fetchurl {
    url = "https://github.com/ModernRelay/omnigraph/releases/download/v0.10.0/omnigraph-linux-x86_64.tar.gz";
    hash = "sha256-BdPOTsCrUah2vv2JtkPD5/LVSJvgOYo4zvb7Og0lf8E=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ libgcc ];
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
    platforms = [ "x86_64-linux" ];
  };
}
