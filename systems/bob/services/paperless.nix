{ bobRestoreMarker, ... }:

{
  services.paperless = {
    enable = true;
    address = "127.0.0.1";
    port = 8000;
    dataDir = "/home/docker/paperless/data";
    mediaDir = "/home/docker/paperless/media";
    consumptionDir = "/home/docker/paperless/consume";
    consumptionDirIsPublic = true;
    database.createLocally = true;
    environmentFile = "/home/wonko/docker/paperless.env";
    settings = {
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
      paperless-consumer.unitConfig.ConditionPathExists = bobRestoreMarker;
      paperless-scheduler.unitConfig.ConditionPathExists = bobRestoreMarker;
      paperless-task-queue.unitConfig.ConditionPathExists = bobRestoreMarker;
      paperless-web.unitConfig.ConditionPathExists = bobRestoreMarker;
    };

    tmpfiles.settings."10-bob-native-services"."/home/wonko/docker/paperless.env".z = {
      group = "root";
      mode = "0600";
      user = "root";
    };
  };
}
