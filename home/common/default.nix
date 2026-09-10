{ wonkoosRevision, ... }:
{
  imports = [ ./codex.nix ];

  home = {
    username = "wonko";
    stateVersion = "25.11";
  };

  manual.manpages.enable = false;

  home.file.".config/wonkoos/revision".text = "${wonkoosRevision}\n";
}
