{
  lib,
  pkgs,
  unstable-pkgs,
  ...
}:

let
  codex = pkgs.writeShellScriptBin "codex" ''
    unset GITHUB_PAT_TOKEN GITHUB_TOKEN GH_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN
    exec ${unstable-pkgs.codex}/bin/codex \
      -c 'shell_environment_policy.allow_login_shell=false' \
      "$@"
  '';
  codexGithubMcp = pkgs.writeShellApplication {
    name = "codex-github-mcp";
    runtimeInputs = with pkgs; [
      gh
      github-mcp-server
    ];
    text = ''
      if ! GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)"; then
        echo "codex-github-mcp: GitHub authentication is unavailable; run 'gh auth login'" >&2
        exit 1
      fi
      export GITHUB_PERSONAL_ACCESS_TOKEN
      exec github-mcp-server stdio
    '';
  };
  omnigraph = pkgs.callPackage ../../packages/omnigraph.nix { };
in
{
  home.packages = with pkgs; [
    codex
    codexGithubMcp
    gh
    nodejs
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

  home.file.".codex/rules/omnigraph.rules".text = ''
    prefix_rule(pattern = ["omnigraph"], decision = "allow")
  '';

  home.file.".agents/skills/omnigraph-context" = {
    source = ./skills/omnigraph-context;
    force = true;
  };
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
