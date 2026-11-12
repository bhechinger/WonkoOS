{ pkgs, unstable-pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    environmentVariables.OLLAMA_CONTEXT_LENGTH = "65536";
  };

  programs.opencode = {
    enable = true;
    package = unstable-pkgs.opencode;
    settings = {
      update = "disable";
      enabled_providers = [ "ollama" ];
      model = "ollama/qwen3.5:9b";
      agents.title.model = "ollama/qwen3.5:9b";
      plugins = [
        "superpowers@git+https://github.com/obra/superpowers.git#v7.0.2"
        "@dietrichgebert/ponytail@5.3.3"
      ];
      permissions = [
        {
          action = "external_directory";
          resource = "*";
          effect = "ask";
        }
      ];
      providers.ollama = {
        settings.baseURL = "http://127.0.0.1:11434/v1";
        models."qwen3.5:9b".limit = {
          context = 65536;
          output = 8192;
        };
      };
    };
  };
}
