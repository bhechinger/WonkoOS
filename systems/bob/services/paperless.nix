{ config, lib, ... }:

{
  sops.secrets.paperless-environment = {
    sopsFile = ../secrets/paperless.env.sops;
    format = "binary";
    mode = "0400";
    restartUnits = [
      "paperless-consumer.service"
      "paperless-scheduler.service"
      "paperless-task-queue.service"
      "paperless-web.service"
    ];
  };

  services.paperless = {
    enable = true;
    address = "127.0.0.1";
    port = 8000;
    dataDir = "/home/docker/paperless/data";
    mediaDir = "/home/docker/paperless/media";
    consumptionDir = "/home/docker/paperless/consume";
    consumptionDirIsPublic = false;
    database.createLocally = true;
    environmentFile = config.sops.secrets.paperless-environment.path;
    settings = {
      PAPERLESS_EMAIL_CERTIFICATE_LOCATION = "/var/lib/paperless/proton-bridge-ca.pem";
      PAPERLESS_OCR_LANGUAGE = "eng+por";
      PAPERLESS_PROXY_SSL_HEADER = [
        "HTTP_X_FORWARDED_PROTO"
        "https"
      ];
      PAPERLESS_URL = "https://paperless.4amlunch.net";
    };
  };

  systemd = {
    services = {
      paperless-scheduler = {
        after = [ "protonmail-bridge.service" ];
        wants = [ "protonmail-bridge.service" ];
      };
      paperless-task-queue = {
        after = [ "protonmail-bridge.service" ];
        wants = [ "protonmail-bridge.service" ];
      };
    };
    tmpfiles.settings."10-paperless" = {
      "/var/lib/paperless".d = {
        group = "paperless";
        mode = "0750";
        user = "root";
      };
      "/home/docker/paperless/consume".d.mode = lib.mkForce "0750";
      "/home/docker/paperless/data".d.mode = lib.mkForce "0750";
      "/home/docker/paperless/export".d = {
        group = "paperless";
        mode = "0750";
        user = "paperless";
      };
      "/home/docker/paperless/media".d.mode = lib.mkForce "0750";
    };
  };
}
