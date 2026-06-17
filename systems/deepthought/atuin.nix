{ pkgs, ... }:
{
  # Install atuin (annoyingly already part of the service but that doesn't put it in the path)
  environment.systemPackages = with pkgs; [ atuin ];

  # Enable the atuin sync server
  services = {
    atuin = {
      enable = true;
      openRegistration = true;

      # Keep the default PostgreSQL backend and make the implicit module behavior
      # explicit: this creates the local atuin database and database owner.
      database.createLocally = true;
    };
  };
}
