{ ... }:
{
  programs = {
    atuin = {
      enable = true;
      enableZshIntegration = true;
      daemon.enable = true;
      settings = {
        sync_frequency = "5m";
        sync_address = "http://localhost:8888";
        workspaces = true;
      };
    };
  };
}
