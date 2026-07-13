{
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

  users.users.wonko = {
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
    openssh.authorizedKeys.keys = import ../../common/wonko-keys.nix;
  };
}
