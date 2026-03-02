{ lib, pkgs, ... }:

{
  home = {
    shell = {
      enableZshIntegration = true;
    };
    packages = with pkgs; [
      direnv
      thefuck
    ];
  };

  programs = {
    zsh = {
      enable = true;
      autocd = true;
      syntaxHighlighting.enable = true;
      autosuggestion.enable = true;

      oh-my-zsh = {
        enable = true;
        plugins = [ "git" "thefuck" "direnv" ];
      };

      history = {
        append = true;
        expireDuplicatesFirst = true;
        ignoreAllDups = true;
      };

      sessionVariables = {
        VKD3D_CONFIG = "dxr11,dxr";
        PROTON_ENABLE_NVAPI = "1";
        PROTON_ENABLE_NGX_UPDATER = "1";
        DXVK_NVAPI_DRS_SETTINGS = "0x10E41E01=1,0x10E41E02=1,0x10E41E03=1,0x10E41DF3=0xffffff,0x10E41DF7=0xffffff";
        MANGOHUD = "1";
      };

      shellAliases = {
        ll = "ls -l";
        oci = "oci --auth security_token";
	z = "zeditor .";
      };

      initContent = ''
        bindkey -v
      '';
    };
  };
}
