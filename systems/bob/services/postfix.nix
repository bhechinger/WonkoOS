{
  services.postfix = {
    enable = true;
    rootAlias = "wonko";
    settings.main = {
      append_dot_mydomain = "no";
      inet_interfaces = [ "loopback-only" ];
      inet_protocols = [ "all" ];
      mailbox_size_limit = "0";
      mydestination = [
        "$myhostname"
        "bob.4amlunch.net"
        "bob"
        "localhost.localdomain"
        "localhost"
      ];
      myhostname = "bob.4amlunch.net";
      mynetworks = [
        "127.0.0.0/8"
        "[::ffff:127.0.0.0]/104"
        "[::1]/128"
      ];
      recipient_delimiter = "+";
      relayhost = [ ];
      smtp_tls_security_level = "may";
      smtpd_relay_restrictions = [
        "permit_mynetworks"
        "permit_sasl_authenticated"
        "defer_unauth_destination"
      ];
      smtpd_tls_security_level = "may";
    };
  };
}
