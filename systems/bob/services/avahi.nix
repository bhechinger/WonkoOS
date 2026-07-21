{
  services.avahi = {
    allowInterfaces = [ "internal" ];
    enable = true;
    nssmdns4 = true;
  };
}
