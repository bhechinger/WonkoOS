{ inputs, lib, ... }:

{
  imports = [
    inputs.determinate.homeManagerModules.default
    inputs.spotify-midi-control.homeManagerModules.default
    ../common
    ./zsh.nix
    ./atuin.nix
    ./audio.nix
    ./development.nix
    ./greptile.nix
    ./kubernetes.nix
    ./software.nix
    ./desktop.nix
    ./nix_tools.nix
    ./zenith.nix
    ./games.nix
    ./gamedev.nix
  ];

  home.homeDirectory = "/home/wonko";

  home.activation.migrateOmnigraphContextSkill = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    skill_dir="$HOME/.agents/skills/omnigraph-context"
    skill_file="$skill_dir/SKILL.md"
    if [[ -e "$skill_dir" || -L "$skill_dir" ]]; then
      if [[ ! -v oldGenPath ]]; then
        _iError "Refusing to replace unmanaged path %s" "$skill_dir"
        exit 1
      fi
      old_home_files="$(readlink -e "$oldGenPath/home-files")"
      if [[ -L "$skill_dir" ]]; then
        old_skill_dir="$old_home_files/.agents/skills/omnigraph-context"
        if [[ "$(readlink "$skill_dir")" != "$old_skill_dir" ]]; then
          _iError "Refusing to replace unmanaged path %s" "$skill_dir"
          exit 1
        fi
      else
        if [[ ! -L "$skill_file" ]]; then
          _iError "Refusing to replace unmanaged path %s" "$skill_dir"
          exit 1
        fi
        old_skill="$old_home_files/.agents/skills/omnigraph-context/SKILL.md"
        if [[ "$(readlink "$skill_file")" != "$old_skill" ]]; then
          _iError "Refusing to replace unmanaged path %s" "$skill_file"
          exit 1
        fi
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
}
