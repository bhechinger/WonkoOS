{
  config,
  pkgs,
  sops-nix,
  ...
}:
{
  imports = [ sops-nix.homeManagerModules.sops ];

  sops.gnupg.home = "/home/wonko/.gnupg";

  sops.secrets.circleci-runner-env = {
    sopsFile = ./secrets/circleci-runner-env.sops;
    format = "binary";
  };

  systemd.user.services.circleci-runner = {
    Unit = {
      Description = "CircleCI Runner";
      Requires = [ "sops-nix.service" ];
      After = [
        "sops-nix.service"
        "podman.socket"
      ];
    };

    Service = {
      Restart = "always";
      RestartSec = 10;
      ExecStartPre = "-${pkgs.podman}/bin/podman rm -f circleci-runner";
      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm \
          --name circleci-runner \
          --env CIRCLECI_RUNNER_NAME=brian-home \
          --env-file ${config.sops.secrets.circleci-runner-env.path} \
          circleci/runner-agent:machine-3
      '';
      ExecStop = "-${pkgs.podman}/bin/podman stop circleci-runner";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
