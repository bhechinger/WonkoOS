# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Making nix ready for flakes.
  nix.package = pkgs.nixVersions.stable;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Setting env var to mark this build as bob.
  environment.variables.WONKO_OS_BUILD = "bob";

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Set your time zone.
  time.timeZone = "Europe/Lisbon";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users = {
    defaultUserShell = pkgs.zsh;

    users = {
      wonko = {
        isNormalUser = true;
        home = "/home/wonko";
        description = "Brian Hechinger";
        extraGroups = [ "wheel" "docker" ]; # Enable ‘sudo’ for the user.
        openssh.authorizedKeys.keys = [ "ssh-rsa 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 New Uber Key" ];

        shell = pkgs.zsh;
      };
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    bat
    gzip
    htop
    jq
    iftop
    unzip
    zip
    usbutils
    which
    docker
    docker-compose
    unifi
    git
    lsof
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Zsh
  programs.zsh = {
    enable = true;
  };

  services = {
    openssh.enable = true;

    unifi.enable = true;

    postgresql = {
      enable = true;
      package = pkgs.postgresql_15;
      enableTCPIP = true;
      authentication = pkgs.lib.mkOverride 10 ''
        local all all trust
        host all all 127.0.0.1/32 trust
        host all all ::1/128 trust
      '';
      initialScript = pkgs.writeText "backend-initScript" ''
        CREATE ROLE nixcloud WITH LOGIN PASSWORD 'nixcloud' CREATEDB;
        CREATE DATABASE nixcloud;
        GRANT ALL PRIVILEGES ON DATABASE nixcloud TO nixcloud;
      '';
    };

    nginx = {
      enable = true;
      virtualHosts = {
        "sonarr.4amlunch.net" = {
          enableACME = false;
          forceSSL = false;
          locations."/" = {
            proxyPass = "http://127.0.0.1:8989";
            proxyWebsockets = true;
            extraConfig =
              "proxy_ssl_server_name on;" +
              "proxy_pass_header Authorization;"
            ;
          };
        };
        "jackett.4amlunch.net" = {
          enableACME = false;
          forceSSL = false;
          locations."/" = {
            proxyPass = "http://127.0.0.1:9117";
            proxyWebsockets = true;
            extraConfig =
              "proxy_ssl_server_name on;" +
              "proxy_pass_header Authorization;"
            ;
          };
        };
        "radarr.4amlunch.net" = {
          enableACME = false;
          forceSSL = false;
          locations."/" = {
            proxyPass = "http://127.0.0.1:7878";
            proxyWebsockets = true;
            extraConfig =
              "proxy_ssl_server_name on;" +
              "proxy_pass_header Authorization;"
            ;
          };
        };
      };
    };
  };

#  security.acme = {
#    acceptTerms = true;
#    defaults.email = "wonko@4amlunch.net";
#    certs."4amlunch.net" = {
#      domain = "*.4amlunch.net";
#      dnsProvider = "cloudflare";
#      credentialsFile = "${pkgs.writeText "cloudflare.env" ''
#        CLOUDFLARE_EMAIL=wonko@4amlunch.net
#        CLOUDFLARE_API_KEY=dYYWVPUtgRI7Cs87M6bSsGG-BuhQpto6Ssm7FHy6
#        CF_DNS_API_TOKEN=dYYWVPUtgRI7Cs87M6bSsGG-BuhQpto6Ssm7FHy6
#        CF_ZONE_API_TOKEN=dYYWVPUtgRI7Cs87M6bSsGG-BuhQpto6Ssm7FHy6
#      ''}";
#    };
#  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking = {
    firewall.enable = false;
    hostId = "3f3fb897";
    hostName = "newbob";
    domain = "4amlunch.net";
    dhcpcd.enable = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [{
      address = "10.42.11.99";
      prefixLength = 24;
    }];
    vlans = {
      external = { id=100; interface="eth0"; };
      internal = { id=420; interface="eth0"; };
      guest = { id=410; interface="eth0"; };
    };
    interfaces.internal.ipv4.addresses = [{
      address = "10.42.0.99";
      prefixLength = 24;
    }];
    defaultGateway = "10.42.0.1";
    nameservers = [ "10.42.0.2" "10.42.0.10" "10.42.0.12" ];
  };

  # Docker service deamon
  virtualisation.docker.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}
