{ inputs, config, lib, pkgs, ... }:

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
        {
	  name = "atuin";
	  ensureDBOwnership = true;
	  ensureClauses = {
	    login = true;
	  };
	}
      ];
      ensureDatabases = [ "wonko" "atuin" ];
      authentication = pkgs.lib.mkOverride 10 ''
        #type database  DBuser  auth-method
        # "local" is for Unix domain socket connections only
        local   all             all                                     trust
        # IPv4 local connections:
        host    all             all             127.0.0.1/32            trust
        # IPv6 local connections:
        host    all             all             ::1/128                 trust
        # Allow replication connections from localhost, by a user with the
        # replication privilege.
        local   replication     all                                     trust
        host    replication     all             127.0.0.1/32            trust
        host    replication     all             ::1/128                 trust
        local atuin       atuin     md5
      '';
    };
  };
}
