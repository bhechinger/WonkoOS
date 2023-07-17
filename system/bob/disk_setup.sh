#ip addr add 10.42.11.2/24 dev eth0
#ip route delete default
#ip route add default via 10.42.11.1
#echo "nameserver 8.8.8.8" >> /etc/resolv.conf
#rsync -av wonko@10.42.11.10:projects/NixOS/ NixOS/
nix run github:nix-community/disko --extra-experimental-features nix-command --extra-experimental-features flakes -- --mode zap_create_mount ./disks.nix
#nix-shell -p git
