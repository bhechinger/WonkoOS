{
  pkgs,
  unstable-pkgs,
  ...
}:

let
  proton-ge-ccenter = unstable-pkgs.proton-ge-bin.overrideAttrs (
    oldAttrs:
    assert oldAttrs.version == "GE-Proton11-5";
    {
      steamDisplayName = "GE-Proton11-5-CCenter";
      postInstall = (oldAttrs.postInstall or "") + ''
        rm "$steamcompattool/files" "$steamcompattool/proton"
        cp -rs "$src/files" "$steamcompattool/files"
        chmod -R u+w "$steamcompattool/files"
        cp "$src/proton" "$steamcompattool/proton"

        # Wine resolves these loader symlinks into $src and otherwise bypasses the patched DLL.
        for file_path in \
          files/bin/wine \
          files/bin/wineserver \
          files/lib/wine/i386-unix/ntdll.so \
          files/lib/wine/i386-unix/wine \
          files/lib/wine/i386-unix/wine-preloader \
          files/lib/wine/i386-windows/ntdll.dll \
          files/lib/wine/x86_64-unix/lsteamclient.so \
          files/lib/wine/x86_64-unix/ntdll.so \
          files/lib/wine/x86_64-unix/wine \
          files/lib/wine/x86_64-unix/wine-preloader \
          files/lib/wine/x86_64-unix/wine64 \
          files/lib/wine/x86_64-unix/wine64-preloader \
          files/lib/wine/x86_64-windows/lsteamclient.dll
        do
          rm "$steamcompattool/$file_path"
          cp "$src/$file_path" "$steamcompattool/$file_path"
        done

        chmod u+w "$steamcompattool/files/lib/wine/x86_64-windows/lsteamclient.dll"
        ${pkgs.python3}/bin/python ${./patch-lsteamclient-ccenter.py} \
          "$steamcompattool/files/lib/wine/x86_64-windows/lsteamclient.dll"

        rm "$steamcompattool/files/share/default_pfx/drive_c/windows/system32/lsteamclient.dll"
        ln -s ../../../../../lib/wine/x86_64-windows/lsteamclient.dll \
          "$steamcompattool/files/share/default_pfx/drive_c/windows/system32/lsteamclient.dll"
      '';
    }
  );
in
{

  environment = {
    systemPackages = with pkgs; [
      pkg-config
      mokutil
      vulkan-tools
      dxvk
      home-manager
      i2c-tools
      inetutils
      nix-top
      nvme-cli
      zsh-nix-shell
      nixfmt
      pciutils
      usbutils
      lshw
      spaceship-prompt
      fuse
      fzf
      gnupg
      man
      screen
      sedutil
      jq
      yq
      openssl
      wget
      backblaze-b2
      rclone
      nfs-utils
      lsof
      file
      ripgrep
      gnumake
      btop
      kitty
      zsh-autocomplete
    ];
  };

  programs = {
    gamemode.enable = true;
    gamescope = {
      enable = true;
      args = [
        "-f"
        "-W 2560"
        "-H 1440"
        "--mangoapp"
        "--adaptive-sync"
        "--rt"
      ];
    };
    extra-container.enable = true;
    htop.enable = true;
    iotop.enable = true;
    less.enable = true;
    starship.enable = true;
    traceroute.enable = true;
    usbtop.enable = true;
    wireshark = {
      enable = true;
      package = pkgs.wireshark;
    };
    thunderbird.enable = true;
    mosh.enable = true;
    tmux.enable = true;
    dconf.enable = true; # virt-manager requires dconf to remember settings
    virt-manager.enable = true;

    steam = {
      enable = true;
      protontricks.enable = true;
      extraCompatPackages = [ proton-ge-ccenter ];
    };

    nix-ld = {
      enable = true;
    };

    neovim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
      viAlias = true;
    };

    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-gnome3;
    };

    zsh = {
      enable = true;
    };

    nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/home/wonko/nix/WonkoOS";
    };
  };
}
