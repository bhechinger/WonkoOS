{ pkgs, ... }:
let
  repoRoot = "/home/wonko/projects/nix/WonkoOS";
  targetVersion = "1.7.2";
  unstableFlake = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

  zedUnstableWatch = pkgs.writeShellApplication {
    name = "zed-unstable-watch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nix
      pkgs.nixfmt
      pkgs.perl
      pkgs.home-manager
    ];
    text = ''
      set -euo pipefail

      repo_root=${repoRoot}
      home_dir="$repo_root/home"
      target_version=${targetVersion}
      unstable_flake=${unstableFlake}

      cd "$repo_root"

      echo "Refreshing unstable flake metadata"
      nix flake metadata --refresh "$unstable_flake" >/dev/null

      unstable_version="$(
        nix eval --impure --raw --expr \
          "let flake = builtins.getFlake \"$unstable_flake\"; pkgs = import flake { system = \"x86_64-linux\"; config.allowUnfree = true; }; in pkgs.zed-editor.version"
      )"

      compare="$(
        nix eval --raw --expr \
          "builtins.toString (builtins.compareVersions \"$unstable_version\" \"$target_version\")"
      )"

      echo "Latest unstable zed-editor version: $unstable_version"

      if [ "$compare" -lt 0 ]; then
        echo "unstable zed-editor is still older than $target_version; nothing to do"
        exit 0
      fi

      echo "unstable zed-editor is ready; switching Home Manager back to unstable"

      perl -0pi -e 's/\n    zed-nixpkgs\.url = "github:NixOS\/nixpkgs\/7e1d71cbba1625e0003e8015be354dfaf7b8fee5"; # zed-editor 1\.7\.2\n/\n/s' "$home_dir/flake.nix"
      perl -0pi -e 's/\n      zed-nixpkgs,//s' "$home_dir/flake.nix"
      perl -0pi -e 's/\n      zed-pkgs = import zed-nixpkgs \{\n        inherit system;\n        config = \{\n          allowUnfree = true;\n        \};\n      \};\n//s' "$home_dir/flake.nix"
      perl -0pi -e 's/\n            inherit zed-pkgs;//s' "$home_dir/flake.nix"
      perl -0pi -e 's/\n            \.\/zed-unstable-watch\.nix//s' "$home_dir/flake.nix"

      perl -0pi -e 's/\{\n  pkgs,\n  unstable-pkgs,\n  zed-pkgs,\n  \.\.\.\n\}:/{ pkgs, unstable-pkgs, ... }:/s' "$home_dir/development.nix"
      perl -0pi -e 's/zed-pkgs\.zed-editor/unstable-pkgs.zed-editor/g' "$home_dir/development.nix"

      nixfmt "$home_dir/flake.nix" "$home_dir/development.nix"
      nix flake lock "$home_dir" --update-input unstable-nixpkgs
      home-manager switch --flake "$home_dir#wonko"
    '';
  };
in
{
  systemd.user.services.zed-unstable-watch = {
    Unit = {
      Description = "Switch Zed back to nixpkgs-unstable when 1.7.2 is available";
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${zedUnstableWatch}/bin/zed-unstable-watch";
    };
  };

  systemd.user.timers.zed-unstable-watch = {
    Unit = {
      Description = "Daily check for zed-editor 1.7.2 in nixpkgs-unstable";
    };

    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "zed-unstable-watch.service";
    };

    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
