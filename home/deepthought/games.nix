{
  pkgs,
  unstable-pkgs,
  ...
}:

let
  yazsCrashCollector = pkgs.writeShellApplication {
    name = "collect-yazs-crash";
    runtimeInputs = with pkgs; [
      coreutils
      zip
    ];
    text = ''
      steam_root="''${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
      compat_user="$steam_root/steamapps/compatdata/2163330/pfx/drive_c/users/steamuser"
      game_path="Awesome Games Studio/Yet Another Zombie Survivors"
      unity_logs="$compat_user/AppData/LocalLow/$game_path"
      crash_root="$compat_user/AppData/Local/Temp/$game_path/Crashes"
      output_dir="$HOME/Documents/YAZS"
      staging_dir=$(mktemp -d)
      bundle_dir="$staging_dir/YAZS"
      trap 'rm -rf -- "$staging_dir"' EXIT HUP INT TERM

      mkdir -p "$output_dir" "$bundle_dir"
      collected=0

      copy_file() {
        local source=$1
        if [[ -f "$source" ]]; then
          cp -a -- "$source" "$bundle_dir/"
          collected=$((collected + 1))
        fi
      }

      copy_file "$HOME/steam-2163330.log"
      copy_file "$unity_logs/Player.log"
      copy_file "$unity_logs/Player-prev.log"

      shopt -s nullglob dotglob
      crash_entries=("$crash_root"/*)
      shopt -u nullglob dotglob
      if (( ''${#crash_entries[@]} )); then
        cp -a -- "$crash_root" "$bundle_dir/Crashes"
        collected=$((collected + 1))
      fi

      if [[ "$collected" -eq 0 ]]; then
        printf 'No YAZS logs or crash dumps were found.\n' >&2
        exit 1
      fi

      timestamp=$(date -u +%Y%m%dT%H%M%SZ)
      archive="$output_dir/YAZS-logs-$timestamp.zip"
      if [[ -e "$archive" ]]; then
        archive="$output_dir/YAZS-logs-$timestamp-$$.zip"
      fi

      (
        cd "$staging_dir"
        zip -qry "$archive" YAZS
      )
      printf 'Created %s\n' "$archive"
    '';
  };
in
{
  home.file.".local/share/Steam/package/beta".text = "publicbeta";

  home.packages = with pkgs; [
    chiaki-ng
    ryubing
    unstable-pkgs.mame
    mindustry
    r2modman
    heroic
    (prismlauncher.override {
      additionalLibs = [ libXi ];
    })
    javaPackages.compiler.temurin-bin.jdk-25
    mcpelauncher-ui-qt
    unigine-superposition
    python314
    yazsCrashCollector
  ];

  programs = {
    mangohud = {
      enable = true;
      enableSessionWide = true;
      settings = {
        full = true;
        media_player = false;
        vsync = 0;
        no_display = true;
      };
    };
  };
}
