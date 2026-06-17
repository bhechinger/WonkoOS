{ lib, ... }:

{
  services = {
    postgresql = {
      enable = true;
      ensureUsers = [
        {
          name = "wonko";
          ensureDBOwnership = true;
          ensureClauses = {
            superuser = true;
            login = true;
          };
        }
      ];
      ensureDatabases = [ "wonko" ];
      authentication = lib.mkForce ''
        #type database  DBuser  auth-method
        # "local" is for Unix domain socket connections only
        local   all             all                                     peer
        # TCP localhost is intentionally disabled. The managed local roles do
        # not have passwords; use Unix sockets with peer auth for local access.
        host    all             all             127.0.0.1/32            reject
        host    all             all             ::1/128                 reject
        # Allow replication connections from localhost, by a user with the
        # replication privilege.
        local   replication     all                                     peer
        host    replication     all             127.0.0.1/32            reject
        host    replication     all             ::1/128                 reject
      '';
    };
  };
}
