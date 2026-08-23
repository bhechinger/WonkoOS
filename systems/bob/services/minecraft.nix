{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  voicePort = 34934;
  routerApiPort = 18080;
  packSource = ../minecraft/pwppp;
  pack = builtins.fromTOML (builtins.readFile (packSource + "/pack.toml"));
  packVersion = pack.version;
  clientPackFileName = "${pack.name}-${packVersion}.zip";
  minecraftProfile = name: "/nix/var/nix/profiles/per-user/root/minecraft-${name}";
  minecraftDataDir = "/var/lib/minecraft/pwppp";
  minecraftStdin = config.services.minecraft-servers.managementSystem.systemd-socket.stdinSocket.path "pwppp";
  gigglesomethingPackSource = ../minecraft/gigglesomething;
  gigglesomethingPack = builtins.fromTOML (
    builtins.readFile (gigglesomethingPackSource + "/pack.toml")
  );
  gigglesomethingPackVersion = gigglesomethingPack.version;
  gigglesomethingClientPackFileName = "${gigglesomethingPack.name}-${gigglesomethingPackVersion}.zip";
  pwpppVersionInfo = pkgs.writeText "pwppp-version.html" "Modpack ${packVersion} / Minecraft ${pack.versions.minecraft} / NeoForge ${pack.versions.neoforge}";
  gigglesomethingVersionInfo = pkgs.writeText "gigglesomething-version.html" "Modpack ${gigglesomethingPackVersion} / Minecraft ${gigglesomethingPack.versions.minecraft} / Forge ${gigglesomethingPack.versions.forge}";
  gigglesomethingDataDir = "/var/lib/minecraft/gigglesomething";
  gigglesomethingStdin = config.services.minecraft-servers.managementSystem.systemd-socket.stdinSocket.path "gigglesomething";

  whitelistedPlayers = [
    "BlockyJackBauer"
    "io42"
    "BennyPlayerX"
    "IanTheCerato"
  ];
  emptyWhitelistFile = (pkgs.formats.json { }).generate "pwppp-whitelist.json" [ ];
  whitelistCommands =
    "whitelist reload\n" + lib.concatMapStrings (name: "whitelist add ${name}\n") whitelistedPlayers;
  whitelistIsValid = lib.all (
    name: builtins.isString name && builtins.match "[A-Za-z0-9_]{3,16}" name != null
  ) whitelistedPlayers;

  serverPackage =
    (pkgs.minecraftServers."neoforge-${lib.replaceStrings [ "." ] [ "_" ] pack.versions.minecraft}-${
      lib.replaceStrings [ "." ] [ "_" ] pack.versions.neoforge
    }"
    ).override
      { jre_headless = pkgs.graalvmPackages.graalvm-oracle_25; };
  gigglesomethingServerPackage = pkgs.callPackage ../minecraft/forge-server.nix {
    jre = pkgs.temurin-jre-bin-17;
  };
  pwpppProfile = minecraftProfile "pwppp";
  gigglesomethingProfile = minecraftProfile "gigglesomething";
  profileServer =
    name:
    pkgs.writeShellApplication {
      name = "minecraft-server";
      text = ''
        exec ${minecraftProfile name}/server/bin/minecraft-server "$@"
      '';
      meta.mainProgram = "minecraft-server";
    };
  pwpppServerProperties = {
    server-ip = "127.0.0.11";
    server-port = 25566;
    motd = "A NEOFORGE server on ${pack.versions.minecraft}\\nrunning ${pack.name} ${pack.version}";
    max-players = 20;
    online-mode = true;
    white-list = true;
    enforce-whitelist = true;
    enable-rcon = true;
    broadcast-rcon-to-ops = false;
    "rcon.port" = 25575;
    "rcon.password" = "@RCON_PASSWORD@";
  };
  gigglesomethingServerProperties = {
    server-ip = "127.0.0.12";
    server-port = 25567;
    motd = "A FORGE server on ${gigglesomethingPack.versions.minecraft}\\nrunning ${gigglesomethingPack.name} ${gigglesomethingPack.version}";
    max-players = 20;
    online-mode = true;
    white-list = true;
    enforce-whitelist = true;
    enable-rcon = true;
    broadcast-rcon-to-ops = false;
    "rcon.port" = 25576;
    "rcon.password" = "@RCON_PASSWORD@";
  };
  propertiesFormat = pkgs.formats.keyValue { };
  pwpppServerPropertiesFile = propertiesFormat.generate "pwppp-server.properties" pwpppServerProperties;
  gigglesomethingServerPropertiesFile = propertiesFormat.generate "gigglesomething-server.properties" gigglesomethingServerProperties;
  serverList =
    address:
    pkgs.runCommand "servers.dat" { } ''
      ${lib.getExe pkgs.python3} - ${lib.escapeShellArg address} "$out" <<'PY'
      from pathlib import Path
      import struct
      import sys

      address, output = sys.argv[1:]

      def string(value):
          encoded = value.encode()
          return struct.pack(">H", len(encoded)) + encoded

      def named(tag, name, value):
          return bytes([tag]) + string(name) + value

      server = named(8, "name", string("4amlunch"))
      server += named(8, "ip", string(address))
      server += b"\0"
      root = named(9, "servers", b"\x0a" + struct.pack(">i", 1) + server)
      Path(output).write_bytes(b"\x0a\0\0" + root + b"\0")
      PY
    '';
  pwpppServerList = serverList "pwppp.4amlunch.net";
  gigglesomethingServerList = serverList "gigglesomething.4amlunch.net";
  prometheusExporterConfig =
    address:
    pkgs.writeText "prometheus_exporter-server.toml" ''
      [collector]
      jvm = true
      mc = true
      mc_dimension_tick_errors = "LOG"
      mc_entities = true

      [web]
      listen_address = "${address}"
      listen_port = 19565
    '';

  mcRouter = pkgs.buildGoModule rec {
    pname = "mc-router";
    version = "1.44.1";
    src = pkgs.fetchFromGitHub {
      owner = "itzg";
      repo = "mc-router";
      tag = "v${version}";
      hash = "sha256-pSS/qXJwNToVcYOScIKgOO82NS9eusjlwisZyJ0cfvw=";
    };
    # v1.44.1 requires Go 1.26.5, while the pinned nixpkgs has 1.26.4.
    # This changes only the accepted patch release, not the language version.
    postPatch = ''
      substituteInPlace go.mod --replace-fail "go 1.26.5" "go 1.26.4"
    '';
    vendorHash = "sha256-XyplBsGTFQBmzqtujFERxq5/AoMMcA6G3Uhw3Tfyrsg=";
    subPackages = [ "cmd/mc-router" ];
    ldflags = [
      "-s"
      "-w"
      "-X main.version=${version}"
    ];
    meta.mainProgram = "mc-router";
  };

  svcRouter = pkgs.buildGoModule rec {
    pname = "svc-router";
    version = "0.0.2";
    src = pkgs.fetchFromGitHub {
      owner = "JLSchuler99";
      repo = "svc-router";
      tag = "v${version}";
      hash = "sha256-/qUFQPdpop4z99vHen107zDiQk0/+eKrJ1GzqCNAPtE=";
    };
    patches = [ ../minecraft/svc-router-session-cleanup.patch ];
    vendorHash = "sha256-mGKxBRU5TPgdmiSx0DHEd0Ys8gsVD/YdBfbDdSVpC3U=";
    subPackages = [ "cmd/router" ];
    postInstall = ''
      mv "$out/bin/router" "$out/bin/svc-router"
    '';
    meta.mainProgram = "svc-router";
  };

  serverPack = pkgs.fetchPackwizModpack {
    pname = "pwppp-server";
    version = packVersion;
    src = packSource;
    side = "server";
    packHash = "sha256-c0LgbqF+8TvyOk94BQtW8BHsyZayeiR8hrc+3UtMjdU=";
  };
  gigglesomethingServerPack = pkgs.fetchPackwizModpack {
    pname = "gigglesomething-server";
    version = gigglesomethingPackVersion;
    src = gigglesomethingPackSource;
    side = "server";
    packHash = "sha256-bwFgWdqinTL/6fOLecxo+gihT5ippeSjqFji6ixslKA=";
  };

  # Packwiz bundles non-CurseForge entries as JARs. Use matching CurseForge file
  # IDs in the client artifact while retaining reliable Modrinth downloads for
  # the native server build and Packwiz clients.
  clientOxidizedMetadata = pkgs.writeText "create-oxidized.pw.toml" ''
    name = "Create: Oxidized"
    filename = "create_oxidized-0.1.3.jar"
    side = "both"

    [download]
    hash-format = "sha1"
    hash = "fe93a9575174b4993cf3fb5f2aed4dd4431096ee"
    mode = "metadata:curseforge"

    [update]
    [update.curseforge]
    file-id = 6286593
    project-id = 953729
  '';
  clientDesignDecorMetadata = pkgs.writeText "create-design-n-decor.pw.toml" ''
    name = "Create: Design n' Decor"
    filename = "Design-n-Decor-1.21.1-2.2b.jar"
    side = "both"

    [download]
    hash-format = "sha1"
    hash = "ff5f0411a3d82e15d69b65617128f6d54e818e1b"
    mode = "metadata:curseforge"

    [update]
    [update.curseforge]
    file-id = 8156977
    project-id = 923238
  '';

  clientPack = pkgs.runCommand clientPackFileName { nativeBuildInputs = [ pkgs.packwiz ]; } ''
    export HOME="$TMPDIR"
    cp -r ${packSource} pack
    chmod -R u+w pack
    cd pack
    cp ${clientOxidizedMetadata} mods/create-oxidized.pw.toml
    cp ${clientDesignDecorMetadata} mods/create-design-n-decor.pw.toml
    cp ${pwpppServerList} servers.dat
    packwiz refresh
    packwiz curseforge export --output "$out"
  '';
  gigglesomethingClientPack =
    pkgs.runCommand gigglesomethingClientPackFileName
      {
        nativeBuildInputs = [ pkgs.packwiz ];
      }
      ''
        cp -r ${gigglesomethingPackSource} pack
        chmod -R u+w pack
        cd pack
        cp ${gigglesomethingServerList} servers.dat
        packwiz refresh
        packwiz curseforge export --output "$out"
      '';

  siteIndex = pkgs.writeText "minecraft-index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>4amlunch Minecraft</title>
        <style>
          body { color: #eee; background: #181818; font: 1rem system-ui, sans-serif; margin: 2rem auto; max-width: 64rem; padding: 0 1rem; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #555; padding: .7rem; text-align: left; }
          a { color: #8cc8ff; }
        </style>
      </head>
      <body>
        <h1>4amlunch Minecraft servers</h1>
        <table>
          <thead><tr><th>Server</th><th>Hostname</th><th>Version</th><th>Access</th><th>Client pack</th></tr></thead>
          <tbody>
            <tr>
              <td>pwppp</td>
              <td><code>pwppp.4amlunch.net</code></td>
              <td><!--# include virtual="/packs/pwppp/version.html" --></td>
              <td>Whitelist</td>
              <td><a href="/packs/pwppp/client.zip">Download</a></td>
            </tr>
            <tr>
              <td>gigglesomething</td>
              <td><code>gigglesomething.4amlunch.net</code></td>
              <td><!--# include virtual="/packs/gigglesomething/version.html" --></td>
              <td>Whitelist</td>
              <td><a href="/packs/gigglesomething/client.zip">Download</a></td>
            </tr>
          </tbody>
        </table>
      </body>
    </html>
  '';

  minecraftSite = pkgs.runCommand "minecraft-site" { } ''
    mkdir "$out"
    cp ${siteIndex} "$out/index.html"
  '';

  voiceConfig = pkgs.runCommand "pwppp-voicechat-server.properties" { } ''
    substitute ${packSource}/config/voicechat/voicechat-server.properties "$out" \
      --replace-fail 'bind_address=' 'bind_address=127.0.0.11' \
      --replace-fail 'voice_host=' 'voice_host=voice.4amlunch.net:${toString voicePort}'
  '';
  gigglesomethingVoiceConfig = pkgs.writeText "gigglesomething-voicechat-server.properties" ''
    port=24454
    bind_address=127.0.0.12
    voice_host=voice.4amlunch.net:${toString voicePort}
  '';

  packFiles = pkgs.runCommand "pwppp-managed-files" { } ''
    mkdir "$out"
    cp -r ${packSource}/config ${packSource}/datapacks "$out/"
  '';
  gigglesomethingPackFiles = pkgs.runCommand "gigglesomething-managed-files" { } ''
    mkdir "$out"
    cp -r ${gigglesomethingPackSource}/config "$out/"
  '';

  packCheck = pkgs.runCommand "pwppp-pack-check" { nativeBuildInputs = [ pkgs.packwiz ]; } ''
    export HOME="$TMPDIR"
    cp -r ${packSource} refreshed
    chmod -R u+w refreshed
    cp refreshed/index.toml index.toml
    cp refreshed/pack.toml pack.toml
    (cd refreshed && packwiz refresh)
    diff -u index.toml refreshed/index.toml
    diff -u pack.toml refreshed/pack.toml
    diff -qr ${packSource}/config ${packFiles}/config
    diff -qr ${packSource}/datapacks ${packFiles}/datapacks

    ${lib.getExe pkgs.python3} - \
      ${packSource} \
      ${serverPack} \
      ${clientPack} \
      ${pwpppServerList} \
      ${clientOxidizedMetadata} \
      ${clientDesignDecorMetadata} <<'PY'
    from collections import Counter
    import hashlib
    import json
    from pathlib import Path
    import sys
    import tomllib
    import zipfile

    source, server, client, server_list, *override_paths = map(Path, sys.argv[1:])


    def load_toml(path):
        with path.open("rb") as handle:
            return tomllib.load(handle)


    def fail_set(label, expected, actual):
        if expected == actual:
            return
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        raise SystemExit(
            f"{label} mismatch\nmissing: {missing}\nunexpected: {unexpected}"
        )


    def digest(path, algorithm):
        algorithm = algorithm.replace("-", "")
        try:
            with path.open("rb") as handle:
                return hashlib.file_digest(handle, algorithm).hexdigest()
        except ValueError as error:
            raise SystemExit(f"unsupported hash format {algorithm!r} for {path}") from error


    pack = load_toml(source / "pack.toml")
    index = load_toml(source / pack["index"]["file"])
    overrides = {load_toml(path)["name"]: load_toml(path) for path in override_paths}
    unused_overrides = set(overrides)
    server_expected = {}
    client_expected = Counter()
    mapped_server_hashes = {}

    for metadata_path in source.rglob("*.pw.toml"):
        metadata = load_toml(metadata_path)
        side = metadata.get("side") or "both"
        destination = metadata_path.relative_to(source).parent / metadata["filename"]
        destination_string = destination.as_posix()

        if side in {"both", "server"}:
            if destination.parts[0] != "mods":
                raise SystemExit(f"server file is not deployed: {destination_string}")
            server_expected[destination_string] = (
                metadata["download"]["hash-format"],
                metadata["download"]["hash"],
            )

        if side not in {"both", "client"}:
            continue

        curseforge = metadata.get("update", {}).get("curseforge")
        if curseforge is None:
            override = overrides.get(metadata["name"])
            if override is None:
                raise SystemExit(
                    f"client file lacks CurseForge metadata: {destination_string}"
                )
            unused_overrides.remove(metadata["name"])
            if override["filename"] != metadata["filename"]:
                raise SystemExit(
                    f"stale CurseForge mapping for {metadata['name']}: "
                    f"{override['filename']} != {metadata['filename']}"
                )
            curseforge = override["update"]["curseforge"]
            if side in {"both", "server"}:
                mapped_server_hashes[destination_string] = (
                    override["download"]["hash-format"],
                    override["download"]["hash"],
                )

        client_expected[(curseforge["project-id"], curseforge["file-id"])] += 1

    if unused_overrides:
        raise SystemExit(f"unused CurseForge mappings: {sorted(unused_overrides)}")

    server_actual = {
        path.relative_to(server).as_posix()
        for path in (server / "mods").rglob("*")
        if path.is_file()
    }
    fail_set("server mods", set(server_expected), server_actual)
    for relative, (algorithm, expected_hash) in server_expected.items():
        actual_hash = digest(server / relative, algorithm)
        if actual_hash != expected_hash:
            raise SystemExit(f"server mod hash mismatch: {relative}")
    for relative, (algorithm, expected_hash) in mapped_server_hashes.items():
        actual_hash = digest(server / relative, algorithm)
        if actual_hash != expected_hash:
            raise SystemExit(f"stale CurseForge mapping: {relative}")

    with zipfile.ZipFile(client) as archive:
        names = set(archive.namelist())
        manifest = json.loads(archive.read("manifest.json"))
        if manifest["name"] != pack["name"] or manifest["version"] != pack["version"]:
            raise SystemExit("client manifest name or version does not match pack.toml")

        client_actual = Counter(
            (entry["projectID"], entry["fileID"]) for entry in manifest["files"]
        )
        if client_expected != client_actual:
            missing = list((client_expected - client_actual).elements())
            unexpected = list((client_actual - client_expected).elements())
            raise SystemExit(
                f"client manifest mismatch\nmissing: {missing}\nunexpected: {unexpected}"
            )

        bundled_mods = sorted(
            name
            for name in names
            if name.startswith("overrides/mods/") and name.endswith(".jar")
        )
        if bundled_mods:
            raise SystemExit(f"client ZIP bundles non-CurseForge mods: {bundled_mods}")

        override_expected = {
            f"overrides/{entry['file']}"
            for entry in index["files"]
            if not entry.get("metafile", False)
        } | {"overrides/servers.dat"}
        override_actual = {
            name
            for name in names
            if name.startswith("overrides/") and not name.endswith("/")
        }
        fail_set("client overrides", override_expected, override_actual)
        for archive_path in override_expected:
            source_path = (
                server_list
                if archive_path == "overrides/servers.dat"
                else source / archive_path.removeprefix("overrides/")
            )
            if source_path.read_bytes() != archive.read(archive_path):
                raise SystemExit(f"client override mismatch: {archive_path}")
    PY

    touch "$out"
  '';
  gigglesomethingPackCheck =
    pkgs.runCommand "gigglesomething-pack-check"
      {
        nativeBuildInputs = [
          pkgs.packwiz
          pkgs.python3
        ];
      }
      ''
        cp -r ${gigglesomethingPackSource} refreshed
        chmod -R u+w refreshed
        cp refreshed/index.toml index.toml
        cp refreshed/pack.toml pack.toml
        (cd refreshed && packwiz refresh)
        diff -u index.toml refreshed/index.toml
        diff -u pack.toml refreshed/pack.toml
        diff -qr ${gigglesomethingPackSource}/config ${gigglesomethingPackFiles}/config

        python - \
          ${gigglesomethingPackSource} \
          ${gigglesomethingServerPack} \
          ${gigglesomethingClientPack} \
          ${gigglesomethingServerList} <<'PY'
        from collections import Counter
        import json
        from pathlib import Path
        import sys
        import tomllib
        import zipfile

        source, server, client, server_list = map(Path, sys.argv[1:])

        with (source / "pack.toml").open("rb") as handle:
            pack = tomllib.load(handle)

        server_expected = set()
        client_expected = Counter()
        for metadata_path in source.rglob("*.pw.toml"):
            with metadata_path.open("rb") as handle:
                metadata = tomllib.load(handle)
            side = metadata.get("side", "both")
            destination = metadata_path.relative_to(source).parent / metadata["filename"]
            if side in {"both", "server"}:
                if destination.parts[0] != "mods":
                    raise SystemExit(f"server file is not a mod: {destination}")
                server_expected.add(destination.as_posix())
            if side in {"both", "client"}:
                curseforge = metadata["update"]["curseforge"]
                client_expected[(curseforge["project-id"], curseforge["file-id"])] += 1

        server_actual = {
            path.relative_to(server).as_posix()
            for path in (server / "mods").iterdir()
            if path.is_file()
        }
        if server_expected != server_actual:
            raise SystemExit("server mod set does not match Packwiz metadata")

        with zipfile.ZipFile(client) as archive:
            if archive.read("overrides/servers.dat") != server_list.read_bytes():
                raise SystemExit("client server list does not match")
            manifest = json.loads(archive.read("manifest.json"))
            if manifest["name"] != pack["name"] or manifest["version"] != pack["version"]:
                raise SystemExit("client manifest name or version does not match pack.toml")
            client_actual = Counter(
                (entry["projectID"], entry["fileID"]) for entry in manifest["files"]
            )
            if client_expected != client_actual:
                raise SystemExit("client mod set does not match Packwiz metadata")
        PY

        touch "$out"
      '';

  pwpppDeployment = pkgs.runCommand "minecraft-pwppp-deployment" { } ''
    test -e ${packCheck}

    mkdir -p "$out/site/packwiz"
    ln -s ${serverPackage} "$out/server"
    ln -s ${serverPack}/mods "$out/mods"
    cp -r ${packFiles}/config "$out/config"
    cp -r ${packFiles}/datapacks "$out/datapacks"
    chmod -R u+w "$out/config"
    cp ${prometheusExporterConfig "127.0.0.11"} "$out/config/prometheus_exporter-server.toml"
    cp ${voiceConfig} "$out/config/voicechat/voicechat-server.properties"
    cp ${pwpppServerPropertiesFile} "$out/server.properties"
    cp ${pwpppVersionInfo} "$out/site/version.html"
    cp ${clientPack} "$out/site/${clientPackFileName}"
    ln -s ${clientPackFileName} "$out/site/client.zip"
    cp -r ${packSource}/. "$out/site/packwiz/"
  '';

  gigglesomethingDeployment = pkgs.runCommand "minecraft-gigglesomething-deployment" { } ''
    test -e ${gigglesomethingPackCheck}

    mkdir -p "$out/config/voicechat" "$out/world/serverconfig" "$out/site/packwiz"
    ln -s ${gigglesomethingServerPackage} "$out/server"
    ln -s ${gigglesomethingServerPack}/mods "$out/mods"
    cp -r ${gigglesomethingPackFiles}/config/. "$out/config/"
    chmod -R u+w "$out/config"
    cp ${gigglesomethingVoiceConfig} "$out/config/voicechat/voicechat-server.properties"
    cp ${prometheusExporterConfig "127.0.0.12"} \
      "$out/world/serverconfig/prometheus_exporter-server.toml"
    cp ${gigglesomethingServerPropertiesFile} "$out/server.properties"
    cp ${gigglesomethingVersionInfo} "$out/site/version.html"
    cp ${gigglesomethingClientPack} "$out/site/${gigglesomethingClientPackFileName}"
    ln -s ${gigglesomethingClientPackFileName} "$out/site/client.zip"
    cp -r ${gigglesomethingPackSource}/. "$out/site/packwiz/"
  '';

  routerHardening = {
    CapabilityBoundingSet = "";
    DeviceAllow = "";
    DynamicUser = true;
    IPAddressAllow = [
      "localhost"
      "10.42.0.0/24"
    ];
    IPAddressDeny = "any";
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    PrivateUsers = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
  };

  pwpppRcon = "${lib.getExe pkgs.mcrcon} -H 127.0.0.11 -P 25575";
  gigglesomethingRcon = "${lib.getExe pkgs.mcrcon} -H 127.0.0.12 -P 25576";
  minecraftRcon = pkgs.writeShellApplication {
    name = "minecraft-rcon";
    excludeShellChecks = [ "SC1091" ];
    text = ''
      source ${config.sops.templates.minecraft-environment.path}
      export MCRCON_PASS="$RCON_PASSWORD"
      exec ${pwpppRcon} "$@"
    '';
  };
  gigglesomethingMinecraftRcon = pkgs.writeShellApplication {
    name = "gigglesomething-rcon";
    excludeShellChecks = [ "SC1091" ];
    text = ''
      source ${config.sops.templates.minecraft-environment.path}
      export MCRCON_PASS="$RCON_PASSWORD"
      exec ${gigglesomethingRcon} "$@"
    '';
  };
  saveOff = pkgs.writeShellApplication {
    name = "minecraft-save-off";
    excludeShellChecks = [ "SC1091" ];
    text = ''
      source ${config.sops.templates.minecraft-environment.path}
      MCRCON_PASS="$RCON_PASSWORD" ${pwpppRcon} "save-off" "save-all flush"
      if ! MCRCON_PASS="$RCON_PASSWORD" ${gigglesomethingRcon} "save-off" "save-all flush"; then
        MCRCON_PASS="$RCON_PASSWORD" ${pwpppRcon} "save-on"
        exit 1
      fi
    '';
  };
  saveOn = pkgs.writeShellApplication {
    name = "minecraft-save-on";
    excludeShellChecks = [ "SC1091" ];
    text = ''
      source ${config.sops.templates.minecraft-environment.path}
      exitCode=0
      MCRCON_PASS="$RCON_PASSWORD" ${pwpppRcon} "save-on" || exitCode=$?
      MCRCON_PASS="$RCON_PASSWORD" ${gigglesomethingRcon} "save-on" || exitCode=$?
      exit "$exitCode"
    '';
  };
  prepareBackup = pkgs.writeShellApplication {
    name = "minecraft-prepare-backup";
    runtimeInputs = [ pkgs.zfs ];
    text = ''
      zfs destroy -r zpool/var/minecraft@restic 2>/dev/null || true
      trap '${lib.getExe saveOn}' EXIT
      ${lib.getExe saveOff}
      zfs snapshot -r zpool/var/minecraft@restic
    '';
  };
  cleanupBackup = pkgs.writeShellApplication {
    name = "minecraft-cleanup-backup";
    runtimeInputs = [ pkgs.zfs ];
    text = ''
      zfs destroy -r zpool/var/minecraft@restic 2>/dev/null || true
    '';
  };
in
{
  imports = [
    inputs.nix-minecraft.nixosModules.minecraft-servers
    inputs.playit-nixos-module.nixosModules.default
  ];

  assertions = [
    {
      assertion = whitelistIsValid;
      message = "Each Minecraft whitelist entry must be a valid Java player name.";
    }
  ];

  nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];

  environment.systemPackages = [
    gigglesomethingMinecraftRcon
    minecraftRcon
  ];

  sops = {
    secrets = {
      minecraft-rcon-password = {
        sopsFile = ../secrets/minecraft.sops;
        format = "yaml";
        key = "rcon-password";
      };
      minecraft-restic-password = {
        sopsFile = ../secrets/minecraft.sops;
        format = "yaml";
        key = "restic-password";
        mode = "0400";
      };
      playit-secret = {
        sopsFile = ../secrets/playit.toml.sops;
        format = "binary";
        mode = "0400";
      };
    };
    templates.minecraft-environment = {
      content = ''
        RCON_PASSWORD=${config.sops.placeholder.minecraft-rcon-password}
      '';
      owner = "root";
      group = "minecraft";
      mode = "0440";
      restartUnits = [
        "minecraft-server-gigglesomething.service"
        "minecraft-server-pwppp.service"
      ];
    };
  };

  services = {
    minecraft-servers = {
      enable = true;
      eula = true;
      dataDir = "/var/lib/minecraft";
      openFirewall = false;
      environmentFile = config.sops.templates.minecraft-environment.path;
      managementSystem = {
        tmux.enable = false;
        systemd-socket.enable = true;
      };
      servers.pwppp = {
        enable = true;
        autoStart = true;
        restart = "on-failure";
        package = profileServer "pwppp";
        # https://github.com/MeowIce/meowice-flags#the-flags-set (G1GC, below 32 GiB)
        jvmOpts = "-Xms1G -Xmx4G --add-modules=jdk.incubator.vector -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=28 -XX:G1MaxNewSizePercent=50 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=15 -XX:G1MixedGCCountTarget=3 -XX:InitiatingHeapOccupancyPercent=20 -XX:G1MixedGCLiveThresholdPercent=90 -XX:SurvivorRatio=32 -XX:G1HeapWastePercent=5 -XX:+PerfDisableSharedMem -XX:G1SATBBufferEnqueueingThresholdPercent=30 -XX:G1ConcMarkStepDurationMillis=5 -XX:G1RSetUpdatingPauseTimePercent=0 -XX:+UseNUMA -XX:-DontCompileHugeMethods -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000 -XX:ReservedCodeCacheSize=400M -XX:NonNMethodCodeHeapSize=12M -XX:ProfiledCodeHeapSize=194M -XX:NonProfiledCodeHeapSize=194M -XX:NmethodSweepActivity=1 -XX:+UseCriticalJavaThreadPriority -XX:AllocatePrefetchStyle=3 -XX:+AlwaysActAsServerClassMachine -XX:+UseTransparentHugePages -XX:LargePageSizeInBytes=2M -XX:+UseLargePages -XX:+EagerJVMCI -XX:+UseStringDeduplication -XX:+UseAES -XX:+UseAESIntrinsics -XX:+UseFMA -XX:+UseLoopPredicate -XX:+RangeCheckElimination -XX:+OptimizeStringConcat -XX:+UseCompressedOops -XX:+UseThreadPriorities -XX:+OmitStackTraceInFastThrow -XX:+RewriteBytecodes -XX:+RewriteFrequentPairs -XX:+UseFPUForSpilling -XX:+UseFastStosb -XX:+UseNewLongLShift -XX:+UseVectorCmov -XX:+UseXMMForArrayCopy -XX:+UseXmmI2D -XX:+UseXmmI2F -XX:+UseXmmLoadAndClearUpper -XX:+UseXmmRegToRegMoveAll -XX:+EliminateLocks -XX:+DoEscapeAnalysis -XX:+AlignVector -XX:+OptimizeFill -XX:+EnableVectorSupport -XX:+UseCharacterCompareIntrinsics -XX:+UseCopySignIntrinsic -XX:+UseVectorStubs -XX:+UseFastJNIAccessors -XX:+UseInlineCaches -XX:+SegmentedCodeCache -XX:+UseCompactObjectHeaders -Djdk.nio.maxCachedBufferSize=262144 -Djdk.graal.UsePriorityInlining=true -Djdk.graal.Vectorization=true -Djdk.graal.OptDuplication=true -Djdk.graal.DetectInvertedLoopsAsCounted=true -Djdk.graal.LoopInversion=true -Djdk.graal.VectorizeHashes=true -Djdk.graal.EnterprisePartialUnroll=true -Djdk.graal.VectorizeSIMD=true -Djdk.graal.StripMineNonCountedLoops=true -Djdk.graal.SpeculativeGuardMovement=true -Djdk.graal.TuneInlinerExploration=1 -Djdk.graal.LoopRotation=true -Djdk.graal.CompilerConfiguration=enterprise";
        symlinks.mods = "${pwpppProfile}/mods";
        files = {
          config = "${pwpppProfile}/config";
          "world/datapacks" = "${pwpppProfile}/datapacks";
          "server.properties" = "${pwpppProfile}/server.properties";
        };
        serverProperties = pwpppServerProperties;
      };
      servers.gigglesomething = {
        enable = true;
        autoStart = true;
        restart = "on-failure";
        package = profileServer "gigglesomething";
        # https://docker-minecraft-server.readthedocs.io/en/latest/configuration/jvm-options/#enable-meowices-flags
        jvmOpts = "-Xms1G -Xmx4G --add-modules=jdk.incubator.vector -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=28 -XX:G1MaxNewSizePercent=50 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=15 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=3 -XX:InitiatingHeapOccupancyPercent=20 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=0 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -XX:G1SATBBufferEnqueueingThresholdPercent=30 -XX:G1ConcMarkStepDurationMillis=5 -XX:+UseNUMA -XX:-DontCompileHugeMethods -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000 -XX:ReservedCodeCacheSize=400M -XX:NonNMethodCodeHeapSize=12M -XX:ProfiledCodeHeapSize=194M -XX:NonProfiledCodeHeapSize=194M -XX:NmethodSweepActivity=1 -XX:+UseFastUnorderedTimeStamps -XX:+UseCriticalJavaThreadPriority -XX:AllocatePrefetchStyle=3 -XX:+AlwaysActAsServerClassMachine -XX:+UseTransparentHugePages -XX:LargePageSizeInBytes=2M -XX:+UseLargePages -XX:+EagerJVMCI -XX:+UseStringDeduplication -XX:+UseAES -XX:+UseAESIntrinsics -XX:+UseFMA -XX:+UseLoopPredicate -XX:+RangeCheckElimination -XX:+OptimizeStringConcat -XX:+UseCompressedOops -XX:+UseThreadPriorities -XX:+OmitStackTraceInFastThrow -XX:+RewriteBytecodes -XX:+RewriteFrequentPairs -XX:+UseFPUForSpilling -XX:+UseVectorCmov -XX:+UseXMMForArrayCopy -XX:+EliminateLocks -XX:+DoEscapeAnalysis -XX:+AlignVector -XX:+OptimizeFill -XX:+EnableVectorSupport -XX:+UseCharacterCompareIntrinsics -XX:+UseCopySignIntrinsic -XX:+UseVectorStubs -XX:+UseFastStosb -XX:+UseNewLongLShift -XX:+UseXmmI2D -XX:+UseXmmI2F -XX:+UseXmmLoadAndClearUpper -XX:+UseXmmRegToRegMoveAll -XX:UseAVX=2 -XX:UseSSE=4";
        symlinks.mods = "${gigglesomethingProfile}/mods";
        files = {
          config = "${gigglesomethingProfile}/config";
          "world/serverconfig" = "${gigglesomethingProfile}/world/serverconfig";
          "server.properties" = "${gigglesomethingProfile}/server.properties";
        };
        serverProperties = gigglesomethingServerProperties;
      };
    };

    nginx.virtualHosts."minecraft.4amlunch.net" = {
      root = minecraftSite;
      onlySSL = true;
      useACMEHost = "4amlunch.net";
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;
      '';
      locations."/".extraConfig = ''
        limit_except GET HEAD { deny all; }
        ssi on;
      '';
      locations."/packs/pwppp/" = {
        alias = "${pwpppProfile}/site/";
        extraConfig = ''
          limit_except GET HEAD { deny all; }
        '';
      };
      locations."/packs/gigglesomething/" = {
        alias = "${gigglesomethingProfile}/site/";
        extraConfig = ''
          limit_except GET HEAD { deny all; }
        '';
      };
    };

    playit = {
      enable = true;
      secretPath = config.sops.secrets.playit-secret.path;
    };

    sanoid = {
      enable = true;
      datasets."zpool/var/minecraft" = {
        autosnap = true;
        autoprune = true;
        recursive = "zfs";
        hourly = 24;
        daily = 14;
        monthly = 3;
        yearly = 0;
        pre_snapshot_script = lib.getExe saveOff;
        post_snapshot_script = lib.getExe saveOn;
        force_post_snapshot_script = true;
        script_timeout = 60;
      };
    };

    restic.backups.minecraft = {
      repository = "rest:https://restic.4amlunch.net/bob/";
      passwordFile = config.sops.secrets.minecraft-restic-password.path;
      environmentFile = config.sops.templates.bob-restic-environment.path;
      initialize = true;
      extraBackupArgs = [
        "--option"
        "rest.connections=20"
        "--retry-lock"
        "2h"
      ];
      paths = [
        "/var/lib/minecraft/pwppp/.zfs/snapshot/restic"
        "/var/lib/minecraft/gigglesomething/.zfs/snapshot/restic"
      ];
      backupPrepareCommand = lib.getExe prepareBackup;
      backupCleanupCommand = lib.getExe cleanupBackup;
      timerConfig = {
        OnCalendar = "*-*-* 00,04,08,12,16,20:40:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
  };

  users = {
    users.wonko.extraGroups = [ "minecraft" ];
  };

  networking.firewall.interfaces.internal = {
    allowedTCPPorts = [ 25565 ];
    allowedUDPPorts = [ voicePort ];
  };

  system.build.minecraftDeployments = {
    pwppp = pwpppDeployment;
    gigglesomething = gigglesomethingDeployment;
  };

  systemd = {
    services = {
      mc-router = {
        description = "Minecraft hostname router";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = routerHardening // {
          IPAddressAllow = [ "0.0.0.0/0" ];
          ExecStart = "${lib.getExe mcRouter} -port 25565 -mapping pwppp.4amlunch.net=127.0.0.11:25566,gigglesomething.4amlunch.net=127.0.0.12:25567 -connection-rate-limit 10 -webhook-url http://127.0.0.1:${toString routerApiPort}/event";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      svc-router = {
        description = "Simple Voice Chat router";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = routerHardening // {
          ExecStart = "${lib.getExe svcRouter} -svc-binding 0.0.0.0:${toString voicePort} -api-binding 127.0.0.1:${toString routerApiPort}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      playit.serviceConfig.ExecCondition = "${lib.getExe' pkgs.gnugrep "grep"} -qv REPLACE_WITH_PLAYIT_SECRET %d/secret";

      minecraft-server-pwppp = {
        restartIfChanged = lib.mkForce false;
        wants = [ "minecraft-whitelist-pwppp.service" ];
        environment.LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.numactl ];
        serviceConfig = {
          MemoryHigh = "5G";
          MemoryMax = "6G";
          NoNewPrivileges = true;
          OOMPolicy = "stop";
          ProtectSystem = "strict";
          ReadWritePaths = [ minecraftDataDir ];
        };
      };
      minecraft-server-gigglesomething = {
        restartIfChanged = lib.mkForce false;
        wants = [ "minecraft-whitelist-gigglesomething.service" ];
        serviceConfig = {
          MemoryHigh = "5G";
          MemoryMax = "6G";
          NoNewPrivileges = true;
          OOMPolicy = "stop";
          ProtectSystem = "strict";
          ReadWritePaths = [ gigglesomethingDataDir ];
        };
      };

      minecraft-whitelist-pwppp = {
        description = "Apply the declarative pwppp Minecraft whitelist";
        after = [ "minecraft-server-pwppp.service" ];
        partOf = [ "minecraft-server-pwppp.service" ];
        path = [
          pkgs.coreutils
          pkgs.systemd
        ];
        script = ''
          install -d -m 0770 -o minecraft -g minecraft ${minecraftDataDir}
          install -m 0660 -o minecraft -g minecraft ${emptyWhitelistFile} ${minecraftDataDir}/whitelist.json
          if systemctl is-active --quiet minecraft-server-pwppp.service; then
            printf %s ${lib.escapeShellArg whitelistCommands} > ${minecraftStdin}
          fi
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };
      minecraft-whitelist-gigglesomething = {
        description = "Apply the declarative gigglesomething Minecraft whitelist";
        after = [ "minecraft-server-gigglesomething.service" ];
        partOf = [ "minecraft-server-gigglesomething.service" ];
        path = [
          pkgs.coreutils
          pkgs.systemd
        ];
        script = ''
          install -d -m 0770 -o minecraft -g minecraft ${gigglesomethingDataDir}
          install -m 0660 -o minecraft -g minecraft ${emptyWhitelistFile} ${gigglesomethingDataDir}/whitelist.json
          if systemctl is-active --quiet minecraft-server-gigglesomething.service; then
            printf %s ${lib.escapeShellArg whitelistCommands} > ${gigglesomethingStdin}
          fi
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

      restic-backups-minecraft = {
        after = [
          "minecraft-server-gigglesomething.service"
          "minecraft-server-pwppp.service"
        ];
      };

      sanoid = {
        after = [
          "minecraft-server-gigglesomething.service"
          "minecraft-server-pwppp.service"
          "sops-install-secrets.service"
        ];
        requires = [ "sops-install-secrets.service" ];
        serviceConfig.SupplementaryGroups = [ "minecraft" ];
      };
    };
  };
}
