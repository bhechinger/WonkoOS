services.traefik = {
  enable = true;
  dynamicConfigOptions = {
    http.middlewares.prefix-strip.stripprefixregex.regex = "/[^/]+";
    http = {
      services = {
        rtl.loadBalancer.servers = [ { url = "http://169.254.1.29:3000/"; } ];
        spark.loadBalancer.servers = [ { url = "http://169.254.1.17:9737/"; } ];
      };
      routers = {
        rtl = {
          rule = "PathPrefix(`/rtl`,`/rtl/`)";
          entryPoints = [ "websecure" ];
          service = "rtl";
          tls = true;
        };
        spark = {
          rule = "PathPrefix(`/spark`,`/spark/`)";
          entryPoints = [ "websecure" ];
          middlewares = "prefix-strip";
          service = "spark";
          tls = true;
        };
      };
    };
    tcp = {
      services = {
        electrs.loadBalancer.servers = [ { address = "169.254.1.16:50001"; } ];
      };
      routers = {
        electrs = {
          rule = "HostSNI(`*`)";
          entryPoints = [ "electrs" ];
          service = "electrs";
          tls = true;
        };
      };
    };
    tls = {
      certificates = {
        certFile = "/var/lib/traefik/cert.pem";
        keyFile = "/var/lib/traefik/key.pem";
      };
    };
  };
  staticConfigOptions = {
    accessLog = {};
    entryPoints = {
      web = {
        address = ":80";
        http.redirections.entrypoint = {
          to = "websecure";
          scheme = "https";
        };
      };
      websecure.address = ":443";
      electrs.address = ":50002";
    };
  };
};
