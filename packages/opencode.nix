{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  ripgrep,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:

# Match the existing database and v1 plugins; stable nixpkgs is older and v2 changes the plugin API.
stdenv.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = "1.19.5";

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${finalAttrs.version}/opencode-linux-x64-baseline.tar.gz";
    hash = "sha256-F8IA/UsiiZVMwBVSVZ+bbQPsFXst37XrVBRPSRZWMz0=";
  };
  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode "$out/bin/opencode"
    wrapProgram "$out/bin/opencode" --prefix PATH : ${lib.makeBinPath [ ripgrep ]}
    runHook postInstall
  '';

  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";
  versionCheckKeepEnvironment = [
    "HOME"
    "OPENCODE_DISABLE_MODELS_FETCH"
  ];
  env.OPENCODE_DISABLE_MODELS_FETCH = true;

  meta = {
    description = "AI coding agent built for the terminal";
    homepage = "https://github.com/anomalyco/opencode";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "opencode";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
