{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    environmentVariables.OLLAMA_CONTEXT_LENGTH = "65536";
  };

  programs.opencode = {
    enable = true;
    package = pkgs.callPackage ../../packages/opencode.nix { };
    settings = {
      autoupdate = false;
      enabled_providers = [ "ollama" ];
      model = "ollama/qwen3.5:9b";
      small_model = "ollama/qwen3.5:9b";
      plugin = [
        "superpowers@git+https://github.com/obra/superpowers.git#v7.0.2"
        "@dietrichgebert/ponytail@5.3.3"
      ];
      provider.ollama = {
        npm = "@ai-sdk/openai-compatible";
        name = "Ollama (local)";
        options.baseURL = "http://127.0.0.1:11434/v1";
        models."qwen3.5:9b" = {
          name = "Qwen 3.5 9B";
          tool_call = true;
          limit = {
            context = 65536;
            output = 8192;
          };
        };
      };
    };
  };
}
