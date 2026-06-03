{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

{
  security.pam.loginLimits = [
    {
      domain = "wonko";
      item = "nofile";
      type = "hard";
      value = "524288";
    }
  ];

  users.users = {
    wonko = {
      isNormalUser = true;
      description = "Brian Hechinger";
      shell = pkgs.zsh;
      linger = true;
      extraGroups = [
        "wheel"
        "audio"
        "libvirtd"
        "users"
        "docker"
        "kvm"
        "wireshark"
        "onepassword"
        "onepassword-cli"
        "qemu-libvirtd"
        "lp"
        "scanner"
      ];
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDCjP0bzRDkAIZAp6uLfmmp99FKq0TxIAdAlI5d7tcJYtUyf4nt8NXC+gbnowkh57m43vgimKl9YmGwmX3X+zEnBJV0orcCqP0wTe10xSBhii8gSeKxmyAmfwHN+t4TDPDC3pXamGYDR22N+2RD6oXjIW44Z7SdFhTGIHwlRUDTCYv4D3QaFTfBKvaqOl0D+qFzJwwR0gVIp/mnNlPOzzl6VoM4u0m4fpWcuq0lHZnjSlNJsE8x4/uOh9zCXbi58Vha8POIhh2WPkpAONP4UbVPkyI22EWSxJbOuFsDeKL/DkCvfnCDBJpOd9l6HUmwZ0pHXb1lON+H61+wKlQcBFRPdlWs8KgpCJq11kuRD4pTB7HfH195uytcV02vcy2Ye2YLaOKC+sI0SP5xz99CYeR9sxCe3zg3OoRjQqO5J+fMVb0xQvWr549I42KqP4jlXS0Jgb8XX/nTuu64AK4zi4eX97GQIOoA9W+T6kliInGZWBjpMv2tOHh6B8D4OtZHJuT9jaeE/hvDLW1iFb+wQG8x6FNmeaFu/5+3sliAHJbxzaxRT9S6okYo3bR+lRE2dlKYn3QWLeOn/yRacFQapA+Cl14OqyxxP9iU9BOg7XJcvIAl22cFXaK3zm/4iy36UNjbu+zRuv/dXBytAEc1C7CsRqoiGhJhjrzRQ3ogTCfITw== wonko@4mlunch.net"
        "ssh-rsa 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 New Uber Key"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCuJCWOjC5DjMZkbNvb4+Ma/qP1U0/rWV854rnU819TAR/+mH58I06nWK0m5a2b6e1k61V8ZXn+gB8SpsBSeDS4kNQNzrAtIZC7vJnfz55dHwGfqWbHGDeH5yujuTrPnHD4Ip4WAIUlgMo24z4d658Kz7SA/KqZiXvQNKuUrRdLPckUzAwqa0FeboRx68NJDrHv9tOEStSIeJCVLV0AJeGz3Fztz0uS1eVZzXLVurSSwuJXiReq7hgaec3UWXHz8KYiqp/hyLaJVWnDMEnYiidZGwal7jxePpM7iVSHAdyh2m1FK8tgbM7f8m7TkcKoh1vO1umGNM693130ghaZIpCCWva8TpvvmANN7TNKtay+/oec3Mq/kim5xNjlskJy2gVu/1AoG6C/N21eCrhOalYP1iFeqXzNDHsWaKmQ0iDUFDY3yGwlDTShCkD7jrMaBiEA+h/ndicT8e2z6z9T3DeJCKGDW3kz++6TJQnXb0amUmNDYaAFD/HILuOg0dd6dxoxQB+m/dfm1oBpb3gycLw5ZjmbYaNy/I+cbw9QYccHI+I0ZPNfkEEcyqslXnFEJ2gs0LABi0sFIu4mZfaEorE4Yw60d2vekCYf3LG8v+QWH72gysGUmXaV1x9lozqt+1ose7a6YJF01oybjBtJmLKJZgvj1L4ax5YQ+j4yCPlZ0Q== cardno:000615099390"
      ];
    };
  };
}
