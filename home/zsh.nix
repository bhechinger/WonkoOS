{
  config,
  lib,
  pkgs,
  sops-nix,
  ...
}:

{
  imports = [ sops-nix.homeManagerModules.sops ];

  sops.gnupg.home = "/home/wonko/.gnupg";
  sops.secrets."github-pat-token" = {
    sopsFile = ./secrets/github-pat-token.sops;
    format = "binary";
  };

  systemd.user.services.sops-unlock = {
    Unit = {
      Description = "Unlock the YubiKey for sops-nix";
      Before = [ "sops-nix.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "sops-unlock" ''
        ${pkgs.sops}/bin/sops --decrypt ${./secrets/github-pat-token.sops} >/dev/null
      '';
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  systemd.user.services.sops-nix = {
    Unit = {
      Requires = [ "sops-unlock.service" ];
      After = [ "sops-unlock.service" ];
    };
    Install.WantedBy = lib.mkForce [ "hyprland-session.target" ];
  };

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
        #VKD3D_CONFIG = "dxr11,dxr";
        #PROTON_ENABLE_NVAPI = "1";
        #PROTON_ENABLE_NGX_UPDATER = "1";
        #DXVK_NVAPI_DRS_SETTINGS = "0x10E41E01=1,0x10E41E02=1,0x10E41E03=1,0x10E41DF3=0xffffff,0x10E41DF7=0xffffff";
        PROTON_LOG = "1";
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
