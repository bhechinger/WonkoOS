{
  fetchurl,
  jre,
  jq,
  lib,
  linkFarm,
  makeWrapper,
  runCommand,
  stdenvNoCC,
  udev,
  unzip,
  writeShellApplication,
  zip,
}:

let
  minecraftVersion = "1.20.1";
  forgeVersion = "47.4.10";
  libraries = builtins.fromJSON (builtins.readFile ./forge-1.20.1-47.4.10-libraries.json);
  repository = linkFarm "forge-${minecraftVersion}-${forgeVersion}-libraries" (
    map (library: {
      name = library.path;
      path = fetchurl {
        inherit (library) url sha1;
      };
    }) libraries
    ++ [
      {
        name = "net/minecraft/server/${minecraftVersion}/server-${minecraftVersion}.jar";
        path = minecraftServer;
      }
    ]
  );
  minecraftServer = fetchurl {
    url = "https://piston-data.mojang.com/v1/objects/84194a2f286ef7c14ed7ce0090dba59902951553/server.jar";
    sha1 = "84194a2f286ef7c14ed7ce0090dba59902951553";
  };
  serverMappings = fetchurl {
    url = "https://piston-data.mojang.com/v1/objects/0b4dba049482496c507b2387a73a913230ebbd76/server.txt";
    sha1 = "0b4dba049482496c507b2387a73a913230ebbd76";
  };
  installer-unwrapped = fetchurl {
    url = "https://maven.minecraftforge.net/net/minecraftforge/forge/${minecraftVersion}-${forgeVersion}/forge-${minecraftVersion}-${forgeVersion}-installer.jar";
    hash = "sha256-GRJ2C0y2uAPYqCbeYDyQdrHacewnZemh+MHKePZSeOM=";
  };
  installer =
    let
      # Seed the online-only Forge installer with its pinned vanilla inputs.
      installer-with-mappings =
        runCommand "forge-${minecraftVersion}-${forgeVersion}-offline-installer.jar"
          {
            nativeBuildInputs = [
              jq
              unzip
              zip
            ];
          }
          ''
            install -m 644 -D ${installer-unwrapped} "$out"
            zip -q -d "$out" 'META-INF/*.SF' 'META-INF/*.RSA'
            unzip -p "$out" install_profile.json > install_profile.json
            jq '
              .processors |= ([
                (.[0] | .args = [
                  "--task", "EXTRACT_FILES",
                  "--archive", "{INSTALLER}",
                  "--from", "data/server_mappings.txt",
                  "--to", "{MOJMAPS}"
                ])
              ] + .)
              |
              (.processors[]
                | select(.args[1] == "DOWNLOAD_MOJMAPS")
                | .args) += ["--skipIfExists"]
            ' install_profile.json > patched.json
            mv patched.json install_profile.json
            install -m 644 -D ${serverMappings} data/server_mappings.txt
            install -m 644 -D ${minecraftServer} cache/vanilla/server.jar
            zip -q "$out" \
              install_profile.json \
              data/server_mappings.txt \
              cache/vanilla/server.jar
          '';
    in
    writeShellApplication {
      name = "forge-${minecraftVersion}-${forgeVersion}-offline-installer";
      runtimeInputs = [ jre ];
      text = ''
        installerHome="$TMPDIR/forge-installer-home"
        mkdir -p "$installerHome/.minecraft/libraries"
        mkdir -p "$1"
        cp -r --no-preserve=all ${repository}/* "$installerHome/.minecraft/libraries"
        java -Duser.home="$installerHome" \
          -jar ${installer-with-mappings} --offline --installServer "$1"
      '';
    };
in
stdenvNoCC.mkDerivation {
  pname = "forge";
  version = "${minecraftVersion}-${forgeVersion}";
  dontUnpack = true;
  preferLocalBuild = true;
  buildInputs = [ makeWrapper ];

  buildPhase = ''
    ${lib.getExe installer} "$out"
    args="$out/libraries/net/minecraftforge/forge/${minecraftVersion}-${forgeVersion}/unix_args.txt"
    substituteInPlace "$args" \
      --replace-fail "-DlibraryDirectory=libraries" "-DlibraryDirectory=$out/libraries" \
      --replace-fail "libraries/" "$out/libraries/"
    makeWrapper "${jre}/bin/java" "$out/bin/minecraft-server" \
      ${lib.optionalString stdenvNoCC.hostPlatform.isLinux "--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ udev ]}"} \
      --append-flags "@$args nogui"
  '';

  passthru = {
    inherit installer repository;
    gameVersion = minecraftVersion;
    loaderVersion = forgeVersion;
  };

  meta = {
    description = "Minecraft Forge Server";
    homepage = "https://minecraftforge.net";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "minecraft-server";
    platforms = lib.platforms.unix;
  };
}
