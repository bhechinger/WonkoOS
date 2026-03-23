# WonkoOS

This is the NixOS configuration of all (eventually) my machines.

# random notes to ignore

nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount --flake github:bhechinger/WonkoOS-temp#deepthought

nixos-install --no-write-lock-file --root /mnt --flake github:bhechinger/WonkoOS-temp#deepthought
