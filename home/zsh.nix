{ pkgs, ... }:

{
  home = {
    shell = {
      enableZshIntegration = true;
    };
    packages = with pkgs; [
      nix-direnv
    ];
  };

  programs = {
    bat.enable = true;
    zsh = {
      enable = true;
      autocd = true;
      syntaxHighlighting.enable = true;
      autosuggestion.enable = true;

      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "direnv"
        ];
      };

      history = {
        append = true;
        expireDuplicatesFirst = true;
        ignoreAllDups = true;
      };

      sessionVariables = {
        PROTON_LOG = "1";
        MANGOHUD = "1";
      };

      shellAliases = {
        ll = "ls -l";
        oci = "oci --auth security_token";
        gigglesomething-rcon = "ssh -t wonko@bob.4amlunch.net gigglesomething-rcon";
        pwppp-rcon = "ssh -t wonko@bob.4amlunch.net minecraft-rcon";
        z = "zeditor .";
      };

      initContent = ''
        bindkey -v
      '';
    };
  };
}
