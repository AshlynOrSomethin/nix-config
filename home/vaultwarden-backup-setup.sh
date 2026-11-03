#!/bin/bash
set -euo pipefail
umask 077

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this setup with sudo." >&2
  exit 1
fi

for tool in docker sqlite3 flock tar visudo; do
  command -v "$tool" >/dev/null
done
test -s /home/nix/.local/share/vaultwarden/db.sqlite3
source_dir=$(dirname "$(readlink -f "$0")")
test -f "$source_dir/export.sh"

docker pull ttionya/vaultwarden-backup:latest
image=$(docker image inspect ttionya/vaultwarden-backup:latest --format '{{index .RepoDigests 0}}')
test -n "$image"

install -d -m 0700 /etc/vaultwarden-backup /var/lib/vaultwarden-backup
printf '%s\n' "$image" > /etc/vaultwarden-backup/image
install -o root -g root -m 0755 "$source_dir/export.sh" /usr/local/sbin/vaultwarden-backup-export

sudoers=$(mktemp /etc/sudoers.d/.vaultwarden-backup.XXXXXXXX)
trap 'rm -f -- "$sudoers"' EXIT
printf 'ashlyn ALL=(root) NOPASSWD: /usr/local/sbin/vaultwarden-backup-export ""\n' > "$sudoers"
chmod 0440 "$sudoers"
visudo -cf "$sudoers"
mv "$sudoers" /etc/sudoers.d/vaultwarden-backup
echo "Vaultwarden backup export installed. No listener or remote timer was created."
