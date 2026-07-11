{
  config,
  pkgs,
  ...
}:

{
  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  boot.kernelModules = [ "nct6775" ];

  environment.systemPackages = with pkgs; [
    lm_sensors
  ];

  sops = {
    useSystemdActivation = true;
    secrets.coolercontrol-admin-password = {
      sopsFile = ./secrets/coolercontrol.sops;
      format = "yaml";
      key = "admin-password";
      owner = "wonko";
      group = "users";
      mode = "0400";
    };
  };

  programs.coolercontrol.enable = true;

  systemd.services.coolercontrold = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    preStart = ''
        mkdir -p /etc/coolercontrol

        if [ ! -e /etc/coolercontrol/config.toml ]; then
          cat > /etc/coolercontrol/config.toml <<'EOF'
      [devices]
      [legacy690]
      [device-settings]

      [[profiles]]
      uid = "0"
      name = "Unmanaged"
      p_type = "Default"
      function_uid = "0"

      [[functions]]
      uid = "0"
      name = "Default Function"
      f_type = "Identity"

      [settings]
      apply_on_boot = true
      EOF
        fi

        ${pkgs.python3}/bin/python3 <<'PY'
      from pathlib import Path

      config_path = Path("/etc/coolercontrol/config.toml")
      text = config_path.read_text()

      start = "# BEGIN wonko radiator curve\n"
      end = "# END wonko radiator curve\n"
      if start in text and end in text:
          before, rest = text.split(start, 1)
          _, after = rest.split(end, 1)
          text = before.rstrip() + "\n\n" + after.lstrip()

      nct_uid = "00a4da18625f56275c89e2fcd25a83c08c5ad3326452fa7e252fcc8a89c92493"
      cpu_uid = "7febede677f5a27c6d57f4e861c5b2d0dfa83925bcb071314dc6132bf6fcfc16"
      gpu_uid = "568337579da7d84e9da34a40400764635a1b25773ca66f11a4dcb7b2d03050fc"
      profile_uid = "radiator-max-cpu-gpu"
      curve = "[[35.0, 30], [50.0, 40], [65.0, 60], [75.0, 80], [83.0, 100]]"

      block = (
          f"{start}"
          "[[profiles]]\n"
          'uid = "radiator-cpu-curve"\n'
          'name = "Radiator CPU Curve"\n'
          'p_type = "Graph"\n'
          f"speed_profile = {curve}\n"
          f'temp_source = {{ temp_name = "temp1", device_uid = "{cpu_uid}" }}\n'
          'function_uid = "0"\n'
          "\n"
          "[[profiles]]\n"
          'uid = "radiator-gpu-curve"\n'
          'name = "Radiator GPU Curve"\n'
          'p_type = "Graph"\n'
          f"speed_profile = {curve}\n"
          f'temp_source = {{ temp_name = "GPU Temp", device_uid = "{gpu_uid}" }}\n'
          'function_uid = "0"\n'
          "\n"
          "[[profiles]]\n"
          f'uid = "{profile_uid}"\n'
          'name = "Radiator Max CPU/GPU"\n'
          'p_type = "Mix"\n'
          'member_profile_uids = ["radiator-cpu-curve", "radiator-gpu-curve"]\n'
          'mix_function_type = "Max"\n'
          'function_uid = "0"\n'
          "\n"
          f"[device-settings.{nct_uid}]\n"
          f'fan2 = {{ profile_uid = "{profile_uid}" }}\n'
          f'fan5 = {{ profile_uid = "{profile_uid}" }}\n'
          f'fan7 = {{ profile_uid = "{profile_uid}" }}\n'
          f"{end}"
      )

      marker = "\n# Cooler Control Settings\n"
      if marker in text:
          text = text.replace(marker, "\n" + block + "\n" + marker, 1)
      else:
          text = text.rstrip() + "\n\n" + block

      config_path.write_text(text)
      PY
    '';
    postStart = ''
      set -eu

      password_file=${config.sops.secrets.coolercontrol-admin-password.path}
      password="$(cat "$password_file")"
      url="https://127.0.0.1:11987"
      auth_file="$(mktemp)"
      cookie_file="$(mktemp)"
      trap 'rm -f "$auth_file" "$cookie_file"' EXIT
      printf 'machine 127.0.0.1 login CCAdmin password %s\n' "$password" > "$auth_file"
      chmod 600 "$auth_file"

      for _ in $(seq 1 60); do
        if ${pkgs.curl}/bin/curl -fsk -X GET "$url/handshake" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      if ${pkgs.curl}/bin/curl -fsk --netrc-file "$auth_file" -X POST "$url/login" -H 'content-type: application/json' --data '{}' >/dev/null; then
        exit 0
      fi

      if ! ${pkgs.curl}/bin/curl -fsk -u CCAdmin:coolAdmin -c "$cookie_file" -X POST "$url/login" -H 'content-type: application/json' --data '{}' >/dev/null; then
        echo "coolercontrold password is neither the SOPS secret nor the default password" >&2
        exit 1
      fi

      ${pkgs.curl}/bin/curl -fsk -b "$cookie_file" --netrc-file "$auth_file" -X POST "$url/set-passwd" -H 'content-type: application/json' --data "{\"current_password\":\"coolAdmin\"}" >/dev/null
    '';
  };

  hardware = {
    # Enable only after pwmconfig finds stable fan*_input/pwm* paths for this board.
    fancontrol.enable = false;

    graphics = {
      enable = true;
      enable32Bit = true;
    };

    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;

      open = true;

      nvidiaSettings = true;

      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    sane = {
      enable = true;
      extraBackends = [ pkgs.hplipWithPlugin ];
      disabledDefaultBackends = [
        "escl"
        "v4l"
      ];
    };
  };
}
