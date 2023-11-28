# In VM console
ip addr add 10.42.11.2/24 dev eth0
ip route delete default
ip route add default via 10.42.11.1
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
passwd

# After ssh-ed into the VM
nix-shell -p git
mkdir nix; cd nix
rsync -av wonko@10.42.11.10:projects/NixOS/everything-nix/ ./
sudo nix run github:nix-community/disko --extra-experimental-features nix-command --extra-experimental-features flakes -- --mode zap_create_mount ./hosts/nixos/newbob/partitions.nix --arg disks '[ "/dev/vda" ]'
sudo mkdir -p /mnt/persist/state/etc/ssh
sudo scp wonko@10.42.11.10:/home/wonko/projects/NixOS/secrets/keys/newbob/* /mnt/persist/state/etc/ssh/
#sudo nixos-generate-config --no-filesystems --root /mnt
sudo nixos-install --flake .#newbob
sudo reboot

sudo nixos-rebuild switch --flake .#newbob
