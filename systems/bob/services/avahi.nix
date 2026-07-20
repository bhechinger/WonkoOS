{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  users.users.avahi.uid = 992;
}
