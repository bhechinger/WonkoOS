{
  config,
  lib,
  pkgs,
  ...
}:

let
  accountId = "6448081fd479386e4adab4d96ccfe8d5";
  zoneId = "50e75230ae53eaa54f02f0834c900fdf";
  tunnelId = "9abf5de3-8a12-4350-8e2f-06b59bb595b0";
  tunnelTarget = "${tunnelId}.cfargotunnel.com";
  tunnelConfig = pkgs.writeText "cloudflare-tunnel-config.json" (
    builtins.toJSON {
      ingress = [
        {
          hostname = "paperless.4amlunch.net";
          service = "https://localhost:443";
          originRequest = {
            httpHostHeader = "paperless.4amlunch.net";
            originServerName = "paperless.4amlunch.net";
          };
        }
        {
          hostname = "minecraft.4amlunch.net";
          service = "https://localhost:443";
          originRequest = {
            httpHostHeader = "minecraft.4amlunch.net";
            originServerName = "minecraft.4amlunch.net";
          };
        }
        {
          hostname = "pwppp.4amlunch.net";
          service = "tcp://localhost:25565";
          originRequest = { };
        }
        {
          hostname = "gigglesomething.4amlunch.net";
          service = "tcp://localhost:25565";
          originRequest = { };
        }
        { service = "http_status:404"; }
      ];
      warp-routing.enabled = false;
    }
  );
  dnsRecords = pkgs.writeText "cloudflare-dns-records.json" (
    builtins.toJSON [
      {
        type = "CNAME";
        name = "paperless.4amlunch.net";
        content = tunnelTarget;
        ttl = 1;
        proxied = true;
      }
      {
        type = "CNAME";
        name = "minecraft.4amlunch.net";
        content = tunnelTarget;
        ttl = 1;
        proxied = true;
      }
      {
        type = "CNAME";
        name = "pwppp.4amlunch.net";
        content = tunnelTarget;
        ttl = 1;
        proxied = true;
      }
      {
        type = "TXT";
        name = "pwppp.4amlunch.net";
        content = "cloudflared-use-tunnel";
        ttl = 1;
        proxied = false;
      }
      {
        type = "CNAME";
        name = "gigglesomething.4amlunch.net";
        content = tunnelTarget;
        ttl = 1;
        proxied = true;
      }
      {
        type = "TXT";
        name = "gigglesomething.4amlunch.net";
        content = "cloudflared-use-tunnel";
        ttl = 1;
        proxied = false;
      }
      {
        type = "A";
        name = "voice.4amlunch.net";
        content = "147.185.221.19";
        ttl = 1;
        proxied = false;
      }
    ]
  );
  cloudflareTunnelSync = pkgs.writeTextFile {
    name = "cloudflare-tunnel-sync";
    executable = true;
    destination = "/bin/cloudflare-tunnel-sync";
    text = ''
      #!${lib.getExe pkgs.python3}
      ${lib.removePrefix "#!/usr/bin/env python3\n" (
        builtins.readFile ../../../scripts/cloudflare-tunnel-sync.py
      )}
    '';
  };
in
{
  sops.secrets.cloudflared-environment = {
    sopsFile = ../secrets/cloudflared.env.sops;
    format = "binary";
    mode = "0400";
    restartUnits = [ "cloudflared-tunnel.service" ];
  };
  sops.secrets.cloudflare-acme-token.restartUnits = [ "cloudflare-tunnel-sync.service" ];

  systemd.services.cloudflare-tunnel-sync = {
    description = "Reconcile the Cloudflare Tunnel and its public DNS";
    after = [
      "network-online.target"
      "sops-install-secrets.service"
    ];
    before = [ "cloudflared-tunnel.service" ];
    requires = [ "sops-install-secrets.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      AmbientCapabilities = "";
      CapabilityBoundingSet = "";
      DynamicUser = true;
      ExecStart = "${cloudflareTunnelSync}/bin/cloudflare-tunnel-sync %d/cloudflare-api-token ${accountId} ${zoneId} ${tunnelId} ${tunnelConfig} ${dnsRecords}";
      LoadCredential = "cloudflare-api-token:${config.sops.secrets.cloudflare-acme-token.path}";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
      # Bob does not currently have a working outbound IPv6 route.
      RestrictAddressFamilies = [ "AF_INET" ];
      RestrictSUIDSGID = true;
      Type = "oneshot";
      UMask = "0077";
    };
  };

  systemd.services.cloudflared-tunnel = {
    after = [
      "cloudflare-tunnel-sync.service"
      "network-online.target"
      "nginx.service"
      "sops-install-secrets.service"
    ];
    requires = [ "sops-install-secrets.service" ];
    wants = [
      "cloudflare-tunnel-sync.service"
      "network-online.target"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      AmbientCapabilities = "";
      CapabilityBoundingSet = "";
      DynamicUser = true;
      EnvironmentFile = config.sops.secrets.cloudflared-environment.path;
      ExecStart = "${lib.getExe pkgs.cloudflared} tunnel --no-autoupdate run";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      Restart = "always";
      RestartSec = "5s";
      RestrictSUIDSGID = true;
    };
  };
}
