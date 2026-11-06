import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import time

import migrate as common


STATE = Path("/var/lib/gatus-transition")
STANDALONE = (
    Path("/var/lib/uptime-kuma"),
    Path("/var/lib/private/uptime-kuma"),
    Path("/etc/docker-compose/UptimeKuma/data"),
)
BACKUP_ROOTS = (
    Path("/var/backups/native-services"),
    Path("/var/backups/shared-mariadb"),
)
KUMA_NAMES = ("uptime-kuma", "private-uptime-kuma", "kuma-mariadb.sql", "kuma-counts.json")


def cleanup_paths():
    paths = list(STANDALONE)
    for root in BACKUP_ROOTS:
        if not root.exists():
            continue
        if root.is_symlink():
            raise RuntimeError(f"Refusing a symlinked backup root: {root}")
        for backup in sorted(root.iterdir()):
            if not re.fullmatch(r"\d{8}T\d{6}Z", backup.name):
                continue
            if backup.is_symlink() or not backup.is_dir():
                raise RuntimeError(f"Unexpected backup path: {backup}")
            for base in (backup, backup / "unfinished-native-copies"):
                if base.is_symlink():
                    raise RuntimeError(f"Refusing symlinked archive: {base}")
                paths.extend(base / name for name in KUMA_NAMES)
    return [path for path in paths if path.exists() or path.is_symlink()]


def delete_kuma_data():
    paths = cleanup_paths()
    common.save_json(STATE / "kuma-cleanup.json", {
        "status": "deleting",
        "paths": list(map(str, paths)),
        "retained": "Shared multi-application database directories and full migration backups",
    })
    for path in paths:
        if not path.is_symlink() and path.resolve() != path:
            raise RuntimeError(f"Refusing cleanup through a symlinked parent: {path}")
        print(f"Deleting Kuma-only data: {path}", flush=True)
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
        else:
            raise RuntimeError(f"Unexpected cleanup file type: {path}")
        if path.name == "kuma-mariadb.sql":
            checksums = path.parent / "sha256.json"
            if checksums.exists():
                values = json.loads(checksums.read_text())
                values.pop(path.name, None)
                common.save_json(checksums, values)
    if cleanup_paths():
        raise RuntimeError("Some Kuma-only data remains after cleanup.")
    common.save_json(STATE / "kuma-cleanup.json", {
        "status": "complete",
        "paths": list(map(str, paths)),
        "retained": "Shared multi-application database directories and full migration backups",
    })


def verify_monitoring():
    common.run(["systemctl", "is-active", "--quiet", "gatus", "nginx", "postgresql"])
    common.wait_http("http://127.0.0.1:3001/")
    for _ in range(90):
        counts = common.postgres_query("gatus", """
            SELECT count(DISTINCT e.endpoint_id),
                   count(DISTINCT e.endpoint_id) FILTER (WHERE r.success)
            FROM endpoints e JOIN endpoint_results r USING (endpoint_id);
        """).strip()
        if counts == "12|12":
            break
        time.sleep(2)
    else:
        raise RuntimeError(f"Expected 12 successful monitored endpoints, got {counts}; inspect Gatus logs.")
    for query, expected, label in [
        ("SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='gatus';", "gatus", "database owner"),
        ("SELECT rolsuper OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname='gatus';", "f",
         "non-privileged database role"),
        ("SHOW listen_addresses;", "", "Unix-socket-only database"),
    ]:
        common.assert_equal(expected, common.postgres_query("gatus", query).strip(), label)
    for unit in ["uptime-kuma", "docker-mariadb"]:
        if common.run(["systemctl", "is-active", "--quiet", unit], check=False).returncode == 0:
            raise RuntimeError(f"Retired service unexpectedly running: {unit}")
    failures = common.failed_units()
    if failures:
        raise RuntimeError(f"Failed units remain: {failures}")


def prepare_postgres(system):
    unit = (system / "etc/systemd/system/postgresql-setup.service").read_text()
    commands = re.findall(r"^ExecStart=(/nix/store/\S+)\s*$", unit, re.MULTILINE)
    if len(commands) != 1 or not Path(commands[0]).is_file():
        raise RuntimeError("Expected one executable PostgreSQL setup script in the target system.")
    common.run(["systemctl", "start", "postgresql.service"])
    # Activation can start the old setup unit before reloading the new unit files.
    # Run the target's idempotent setup without restarting existing database clients.
    common.run(["runuser", "-u", "postgres", "--", "env", f"PATH={os.environ['PATH']}",
                "PGPORT=5432", commands[0]])


def activate(system, delete_old_data):
    if not system.is_relative_to("/nix/store") or not (system / "bin/switch-to-configuration").is_file():
        raise RuntimeError("Pass the built NixOS system store path.")
    units = system / "etc/systemd/system"
    if not (units / "gatus.service").exists() or (units / "uptime-kuma.service").exists():
        raise RuntimeError("Target must enable Gatus and leave Kuma retired.")
    common.check_supervisors(system, False)
    STATE.mkdir(mode=0o700, exist_ok=True)
    for name, target in [("previous-system", str(Path("/run/current-system").resolve())),
                         ("target-" + system.name, str(system))]:
        if not (STATE / name).exists():
            common.run(["nix-store", "--add-root", str(STATE / name), "--indirect", "--realise", target])
    prepare_postgres(system)
    common.run(["systemctl", "reset-failed", "gatus.service"])
    common.run([str(system / "bin/switch-to-configuration"), "test"])
    common.run(["systemctl", "start", "postgresql.target", "gatus"])
    verify_monitoring()
    common.run(["nix-env", "--profile", "/nix/var/nix/profiles/system", "--set", str(system)])
    common.run([str(system / "bin/switch-to-configuration"), "boot"])
    if delete_old_data:
        delete_kuma_data()
    print("Gatus active and persistent; 12 monitors verified with PostgreSQL history.", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Activate native Gatus and optionally delete Kuma-only data.")
    parser.add_argument("--system", type=Path, required=True)
    parser.add_argument("--delete-kuma-data", action="store_true",
                        help="Delete standalone Kuma state and Kuma-only backup copies/dumps, not shared backups")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Run with sudo in your terminal.")
    os.umask(0o077)
    with Path("/run/lock/gatus-transition.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        activate(args.system.resolve(), args.delete_kuma_data)


if __name__ == "__main__":
    main()
