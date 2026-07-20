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
    # Include both installed OCR languages. paperless.env keeps English as
    # the existing runtime default.
    settings.PAPERLESS_OCR_LANGUAGE = "eng+por";
  };

  systemd.services = {
    paperless-consumer.unitConfig.ConditionPathExists = bobRestoreMarker;
    paperless-scheduler.unitConfig.ConditionPathExists = bobRestoreMarker;
    paperless-task-queue.unitConfig.ConditionPathExists = bobRestoreMarker;
    paperless-web.unitConfig.ConditionPathExists = bobRestoreMarker;
  };
}
