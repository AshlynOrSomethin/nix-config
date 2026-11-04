#!/bin/bash
set -euo pipefail
umask 077

if [ "$#" -ne 0 ]; then
  echo "This command does not accept arguments." >&2
  exit 1
fi

exec 9>/run/lock/vaultwarden-backup.lock
flock -n 9

data=/home/nix/.local/share/vaultwarden
test -s "$data/db.sqlite3"
work=$(mktemp -d /var/lib/vaultwarden-backup/run.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/config" "$work/export"
printf '[LocalBackup]\ntype = local\n' > "$work/config/rclone.conf"
image=$(cat /etc/vaultwarden-backup/image)

docker run --rm --pull=never --network=none \
  --mount "type=bind,source=$data,target=/data,readonly" \
  --mount "type=bind,source=$work/config,target=/config" \
  --mount "type=bind,source=$work/export,target=/export" \
  -e DATA_DIR=/data \
  -e RCLONE_CONFIG=/config/rclone.conf \
  -e RCLONE_REMOTE_NAME=LocalBackup \
  -e RCLONE_REMOTE_DIR=/export \
  -e ZIP_ENABLE=FALSE \
  -e BACKUP_KEEP_DAYS=0 \
  -e BACKUP_FILE_SUFFIX=%Y%m%dT%H%M%SZ \
  "$image" backup >&2

mapfile -t databases < <(find "$work/export" -maxdepth 1 -type f -name 'db.*.sqlite3')
if [ "${#databases[@]}" -ne 1 ]; then
  echo "Backup did not produce exactly one SQLite database." >&2
  exit 1
fi
if [ "$(sqlite3 "${databases[0]}" 'PRAGMA quick_check;')" != ok ]; then
  echo "Backup SQLite integrity check failed." >&2
  exit 1
fi

tar -czf - -C "$work/export" .
