{ inputs, config, lib, pkgs, ... }:

{
  nixpkgs.config.permittedInsecurePackages = [
    "qtwebengine-5.15.19"
  ];

  environment = {
    systemPackages = with pkgs; [
      stremio
      pkg-config
      mokutil
      vulkan-tools
      dxvk
      home-manager
      #blockbench
      #bluedevil
      #coolercontrol.coolercontrol-liqctld
      #coolercontrol.coolercontrold
      i2c-tools
      inetutils
      #droidcam
      #fluxcd
      #fractal
      #google-cloud-sdk
      #grafana-alloy
      #inkscape
      #krename
      #krita
      #lapce
      #lime3ds
      #mindustry
      nix-top
      #nix-web
      #nixos-shell
      nvme-cli
      #obexftp
      #obs-studio
      #openobex
      #orca
      #pinentry-all
      #sslscan
      #usbip-linux
      #usbmuxd2-unstable
      #ventoy
      #vlc
      #vulnix
      #xwaylandvideobridge
      zsh-nix-shell
      #glances
      #zenmonitor
      nixfmt
      #davinci-resolve
      ##ffmpeg_5-full
      #stress
      #stress-ng
      #firestarter
      #gpu-burn
      #util-linux
      #kate
      #libsForQt5.kcalc
      pciutils
      #franz
      #whatsapp-for-linux
      #signal-desktop
      ##fractal
      usbutils
      lshw
      spaceship-prompt
      #jotta-cli
      #libreoffice
      #dropbox
      #dropbox-cli
      #corectrl
      fuse
      fzf
      gnupg
      man
      screen
      sedutil
      #thunderbird
      jq
      yq
      openssl
      wget
      #irccloud
      #s-tui
      nfs-utils
      #prismlauncher
      #zulu8
      #zulu17
      #zulu21
      #virt-viewer
      #virtiofsd
      #spice
      #spice-gtk
      #spice-protocol
      #win-virtio
      #win-spice
      #adwaita-icon-theme
      #helix
      lsof
      #wmctrl
      #supercollider
      #supercollider_scel
      #gnuplot
      file
      #lutris
      #wineWow64Packages.stagingFull
      #xorg.xkill
      #virtiofsd
      ripgrep
      #heroic
      #iamb
      #irssi
      #nix-prefetch-git
      #nix-prefetch-github
##      inputs.smc.packages.x86_64-linux.default { lib = lib; }
##      inputs.npe.packages.x86_64-linux.default { lib = lib; }
      gnumake
      #xsel
      #xclip
      #vimPlugins.lazy-nvim
      #unzip
      #tree-sitter
      #mailspring
      #rsync
      ##obsidian
      #packwiz
      #todoist
      btop
      ##nheko
      #keycloak
      #weston
      #lzip
      #wofi
      #wofi-pass
      #wofi-emoji
      #waybar
      #hyprpaper
      #zfs-autobackup
      #zfstools
      kitty
      #libheif
      #sqlite
      #moonlight-qt
      #kdePackages.krfb
      #sshfs
      #protonmail-bridge
      #telegram-desktop
      #cdrtools
      #todoist
      #todoist-electron
      #cargo-udeps
      #chromium
      #hplip
      #gscan2pdf
      #backblaze-b2
      #s3fs
      zsh-autocomplete
      #cmctl
      #oxtools
      #pkgs-6_8.linuxKernel.packages.linux_6_8.systemtap
      #gimp-with-plugins
      #xsane
      #unrar
      #protontricks
      #pr-tracker
      #nix-output-monitor
      #nix-tree
      #poppler_utils
      #xorg.libxcvt
      #nvtopPackages.full
      #smartmontools
      #p7zip
      #molly-guard
      #proton-pass
      #inputs.nix-inspect.packages.x86_64-linux.default
      #nmap
      #dig
      #sshpass
      ##keybase
      ##keybase-gui
      #bitwarden-desktop
      #bitwarden-cli
    ];
  };

  programs = {
    gamemode.enable = true;
    gamescope = {
      enable = true;
      args = [
	"--rt"
      ];
    };
    extra-container.enable = true;
    #_1password.enable = true;
    #_1password-gui.enable = true;
    #browserpass.enable = true;
    #direnv.enable = true;
    #evince.enable = true;
    #firefox.enable = true;
    #git.enable = true;
    htop.enable = true;
    iotop.enable = true;
    less.enable = true;
    openvpn3.enable = true;
    starship.enable = true;
    traceroute.enable = true;
    usbtop.enable = true;
    wireshark = {
      enable = true;
      package = pkgs.wireshark;
    };
    thunderbird.enable = true;
    #atop.enable = true;
    #calls.enable = true;
    #chromium = {
    #  enable = true;
    #  plasmaBrowserIntegrationPackage = pkgs.libsForQt5.plasma-browser-integration;
    #};
    #feedbackd.enable = true;
    #gamemode.enable = true;
    #iftop.enable = true;
    mosh.enable = true;
    #thefuck.enable = true;
    tmux.enable = true;
    dconf.enable = true; # virt-manager requires dconf to remember settings
    virt-manager.enable = true;

    steam = {
      enable = true;
      protontricks.enable = true;
    };

    #kdeconnect.enable = true;

    nix-ld = {
      enable = true;
    };

    neovim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
      viAlias = true;
      #configure = {
      #  customRC = ''
      #    set clipboard+=unnamed
      #    set clipboard+=unnamedplus
      #  '';
      #};
    };

    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    zsh = {
      enable = true;
    #  syntaxHighlighting.enable = true;
    #  autosuggestions.enable = true;
    #  ohMyZsh = {
    #    enable = true;
    #    plugins = [ "git" ];
    #  };
    #  #enableCompletetion = false; # so we can use zsh-autocomplete
    };

    nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/home/wonko/projects/nix/WonkoOS-temp/systems/deepthought-new";
    };
  };
}
