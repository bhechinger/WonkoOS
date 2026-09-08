{
  config,
  lib,
  pkgs,
  ...
}:

let
  homeDirectory = config.home.homeDirectory;
  servicePath = lib.makeBinPath [ pkgs.yabai ] + ":/usr/bin:/bin:/usr/sbin:/sbin";
in
{
  home = {
    packages = with pkgs; [
      ansible
      btop
      cloc
      google-cloud-sql-proxy
      egctl
      git
      gnupg
      go
      graphviz
      helm-ls
      inetutils
      irssi
      kubeconform
      kubectl
      kubernetes-helm
      kubo
      libusb1
      pinentry_mac
      podman
      podman-desktop
      postgresql_14
      ripgrep
      rustup
      signal-desktop
      unixtools.watch
      yabai
      yubikey-manager
      yq-go
      zellij
      (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
    ];

    sessionPath = [
      "$HOME/bin"
      "$HOME/.cargo/bin"
      "$HOME/.foundry/bin"
    ];
  };

  programs = {
    atuin = {
      enable = true;
      enableZshIntegration = true;
    };

    direnv = {
      enable = true;
      enableZshIntegration = true;
    };

    zsh = {
      enable = true;
      initContent = ''
        set -o vi
        export SSH_AUTH_SOCK="$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)"
        ${pkgs.gnupg}/bin/gpg-connect-agent updatestartuptty /bye >/dev/null
      '';
    };
  };

  services.skhd = {
    enable = true;
    errorLogFile = "/tmp/skhd_wonko.err.log";
    outLogFile = "/tmp/skhd_wonko.out.log";
  };

  launchd.agents = {
    skhd.config.EnvironmentVariables.PATH = servicePath;

    yabai = {
      enable = true;
      config = {
        EnvironmentVariables.PATH = servicePath;
        KeepAlive = {
          Crashed = true;
          SuccessfulExit = false;
        };
        Nice = -20;
        ProcessType = "Interactive";
        ProgramArguments = [ "${pkgs.yabai}/bin/yabai" ];
        RunAtLoad = true;
        StandardErrorPath = "/tmp/yabai_wonko.err.log";
        StandardOutPath = "/tmp/yabai_wonko.out.log";
      };
    };

    "postgresql-14" = {
      enable = true;
      config = {
        KeepAlive = true;
        ProgramArguments = [
          "${pkgs.postgresql_14}/bin/postgres"
          "-D"
          "${homeDirectory}/.local/share/postgresql/14"
        ];
        RunAtLoad = true;
        StandardErrorPath = "${homeDirectory}/Library/Logs/postgresql-14.log";
        StandardOutPath = "${homeDirectory}/Library/Logs/postgresql-14.log";
        WorkingDirectory = homeDirectory;
      };
    };
  };
}
