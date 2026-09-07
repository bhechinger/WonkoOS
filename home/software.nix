{
  pkgs,
  config,
  lib,
  ...
}:

let
  omnigraph = pkgs.callPackage ../packages/omnigraph.nix { };
  qnap = pkgs.rustPlatform.buildRustPackage rec {
    pname = "qnap";
    version = "0.1.12";
    src = pkgs.fetchFromGitHub {
      owner = "rvben";
      repo = "qnap-cli";
      tag = "v${version}";
      hash = "sha256-Xz75WZeztKHhs3PYsUu38fRBY2YsgCBbml1Lv9yCbfI=";
    };
    cargoHash = "sha256-DKtJ8IPCYq3fOdHZCcpl2mxMKCRho9AmiTol0egpyc8=";
    env.NO_COLOR = "1";
  };
in
{
  home.packages = with pkgs; [
    ncdu
    xlsclients
    fastfetch
    mtr-gui
    rar
    p7zip
    qbittorrent
    irccloud
    dig
    kdePackages.qtsvg
    kdePackages.dolphin
    unzip
    irssi
    wine64
    kdePackages.bluedevil
    droidcam
    fluxcd
    fractal
    i2c-tools
    inetutils
    inkscape
    krename
    krita
    azahar
    nvme-cli
    obexftp
    openobex
    orca
    pinentry-all
    sslscan
    vlc
    telegram-desktop
    signal-desktop
    discord
    slack
    age
    sops
    gimp
    inxi
    mesa-demos
    whatsie
    qnap
    omnigraph
  ];

  home.file.".omnigraph/config.yaml".text = ''
    servers:
      bob:
        url: https://omnigraph.4amlunch.net
    defaults:
      server: bob
      output: table
  '';

  home.file.".agents/skills/omnigraph-context".source = ./skills/omnigraph-context;
  home.activation.migrateOmnigraphContextSkill = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    skill_dir="$HOME/.agents/skills/omnigraph-context"
    skill_file="$skill_dir/SKILL.md"
    if [[ -v oldGenPath && ! -L "$skill_dir" && -L "$skill_file" ]]; then
      old_home_files="$(readlink -e "$oldGenPath/home-files")"
      old_skill="$old_home_files/.agents/skills/omnigraph-context/SKILL.md"
      if [[ "$(readlink "$skill_file")" == "$old_skill" ]]; then
        if [[ -n "$(find "$skill_dir" -mindepth 1 -maxdepth 1 ! -name SKILL.md -print -quit)" ]]; then
          if [[ -v DRY_RUN ]]; then
            backup_dir="$skill_dir.before-directory-link.XXXXXXXX/omnigraph-context"
          else
            backup_dir="$(mktemp -d "$skill_dir.before-directory-link.XXXXXXXX")/omnigraph-context"
          fi
          run mv "$skill_dir" "$backup_dir"
          run rm "$backup_dir/SKILL.md"
        else
          run rm "$skill_file"
          run rmdir "$skill_dir"
        fi
      fi
    fi
  '';

  programs = {
    firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
      policies.SearchEngines.Default = "DuckDuckGo";
    };
    chromium.enable = true;
    obs-studio.enable = true;
    hyprshot = {
      enable = true;
      saveLocation = "$HOME/Pictures/Screenshots";
    };
  };

  services = {
    dropbox.enable = true;
  };
}
