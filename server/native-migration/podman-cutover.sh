set -euo pipefail

if [ "$#" -ne 1 ] || [ "$EUID" -ne 0 ]; then
  echo "Usage: sudo podman-cutover /nix/store/...-nixos-system-server-..." >&2
  exit 2
fi
target=$1
if [ "$(hostname)" != server ] || [ ! -x "$target/bin/switch-to-configuration" ]; then
  echo "Run on server with a built server system as the argument" >&2
  exit 1
fi
if ! grep -Fq 'podman-container-resources.service' "$target/etc/systemd/system/podman-freshrss.service"; then
  echo "The target does not contain the expected Podman migration configuration" >&2
  exit 1
fi
marker=/var/lib/podman-container-migration/ready
if [ -e "$marker" ]; then
  echo "Migration already prepared; inspect the existing state before continuing" >&2
  exit 1
fi

names=(authentik-server-1 authentik-worker-1 bitmagnet chiyogami freshrss grimmory grimmory-mariadb-1 iqbit)
units=()
for name in "${names[@]}"; do
  systemctl is-active --quiet "docker-$name.service" || {
    echo "Expected running Docker service: docker-$name.service" >&2
    exit 1
  }
  if podman container exists "$name"; then
    echo "Podman container already exists: $name" >&2
    exit 1
  else
    status=$?
    if [ "$status" -ne 1 ]; then
      echo "Unable to inspect Podman container $name (exit $status)" >&2
      exit "$status"
    fi
  fi
  units+=("docker-$name.service")
done
for volume in freshrss_data freshrss_extensions; do
  docker volume inspect "$volume" >/dev/null
  if podman volume exists "$volume"; then
    echo "Podman volume already exists: $volume" >&2
    exit 1
  else
    status=$?
    if [ "$status" -ne 1 ]; then
      echo "Unable to inspect Podman volume $volume (exit $status)" >&2
      exit "$status"
    fi
  fi
done
if systemctl is-active --quiet docker-prowlarr.service; then
  units+=("docker-prowlarr.service")
fi
python3 - <<'PY'
import ipaddress
import json
import subprocess
import sys

requested = [ipaddress.ip_network(f"10.246.{n}.0/24") for n in range(1, 9)]
routes = json.loads(subprocess.check_output(["ip", "-j", "-4", "route", "show", "table", "all"]))
used = [ipaddress.ip_network(r["dst"], strict=False) for r in routes if r.get("dst") not in (None, "default")]
for runtime in ("docker", "podman"):
    ids = subprocess.check_output([runtime, "network", "ls", "-q"], text=True).split()
    if not ids:
        continue
    networks = json.loads(subprocess.check_output([runtime, "network", "inspect", *ids]))
    for network in networks:
        subnets = network.get("subnets") or network.get("IPAM", {}).get("Config") or []
        for subnet in subnets:
            value = subnet.get("subnet") or subnet.get("Subnet")
            if value:
                used.append(ipaddress.ip_network(value, strict=False))
for wanted in requested:
    for existing in used:
        if existing.version == wanted.version and wanted.overlaps(existing):
            sys.exit(f"Podman subnet {wanted} overlaps existing network or route {existing}")
PY
for name in "${names[@]}"; do
  image=$(docker inspect --format '{{.Config.Image}}' "$name")
  echo "Copying image $image"
  docker image save "$image" | podman load
done

backup_dir=$(mktemp -d /var/lib/podman-container-migration-backup.XXXXXXXX)
chmod 700 "$backup_dir"
cutover_started=0
restore_on_error() {
  result=$?
  if [ "$result" -ne 0 ]; then
    if [ "$cutover_started" -eq 0 ]; then
      echo "Migration failed before activation; restarting Docker services." >&2
      systemctl start "${units[@]}" || echo "Docker restart failed; inspect services immediately" >&2
    else
      echo "Activation or verification failed. Do not start Docker against live Podman data; inspect services and restore from $backup_dir if needed." >&2
    fi
  fi
}
trap restore_on_error EXIT
systemctl stop docker-grimmory.service docker-grimmory-mariadb-1.service
systemctl stop docker-freshrss.service docker-authentik-worker-1.service docker-authentik-server-1.service docker-bitmagnet.service docker-chiyogami.service docker-iqbit.service
if systemctl is-active --quiet docker-prowlarr.service; then
  systemctl stop docker-prowlarr.service
fi

tar --acls --xattrs --numeric-owner -cpf "$backup_dir/application-data.tar" \
  -C / var/www/FreshRSS etc/docker-compose/grimmory/data \
  etc/docker-compose/grimmory/mariadb/config etc/docker-compose/grimmory/bookdrop \
  etc/docker-compose/authentik/data etc/docker-compose/authentik/certs \
  etc/docker-compose/authentik/custom-templates etc/docker-compose/chiyogami/pastes
for volume in freshrss_data freshrss_extensions; do
  source=$(docker volume inspect --format '{{.Mountpoint}}' "$volume")
  tar --acls --xattrs --numeric-owner -cpf "$backup_dir/$volume.tar" -C "$source" .
  podman volume create "$volume" >/dev/null
  destination=$(podman volume inspect --format '{{.Mountpoint}}' "$volume")
  tar --acls --xattrs --numeric-owner -xpf "$backup_dir/$volume.tar" -C "$destination"
done

install -d -m 700 /var/lib/podman-container-migration
printf '%s\n' "$backup_dir" > "$marker"
chmod 600 "$marker"
cutover_started=1
nix-env -p /nix/var/nix/profiles/system --set "$target"
"$target/bin/switch-to-configuration" switch
for name in "${names[@]}"; do
  systemctl is-active --quiet "podman-$name.service" || {
    echo "Podman service failed: podman-$name.service" >&2
    exit 1
  }
done
for url in \
  http://127.0.0.1:9180/-/health/ready/ \
  http://127.0.0.1:3333/ \
  http://127.0.0.1:8000/ \
  http://127.0.0.1:9900/ \
  http://127.0.0.1:6060/api/v1/healthcheck \
  http://127.0.0.1:8082/; do
  healthy=0
  for _ in {1..60}; do
    if curl --silent --show-error --fail --max-time 3 "$url" >/dev/null 2>&1; then
      healthy=1
      break
    fi
    sleep 2
  done
  if [ "$healthy" -ne 1 ]; then
    echo "Application health check failed: $url" >&2
    exit 1
  fi
done
echo "Podman services and HTTP health checks passed. Backup: $backup_dir"
echo "Verify application health and Authentik outposts before removing Docker."
