import argparse
import base64
from collections import Counter
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import luckperms as single
import migrate as common


SERVERS = (
    "f1bc778c-5820-4778-819c-ce237099b82f",
    "d8899e2b-5987-48e1-a75e-eb810a5e0dd6",
    "bf3c01df-8ea9-447f-8351-f03bbc49668e",
    "26f6c618-ab2c-4b9a-b520-8128f2041f8d",
)
H2_SERVER = SERVERS[-1]
BACKUPS = Path("/var/backups/luckperms-servers")
SOURCE_CONFIG = single.CONFIG


def volume(server):
    return Path("/var/lib/pelican/volumes") / server


def config(server):
    return volume(server) / "plugins/LuckPerms/config.yml"


def inspect(server):
    ids = common.output(["docker", "container", "ls", "--all", "--quiet"]).split()
    containers = json.loads(common.output(["docker", "inspect", *ids])) if ids else []
    matches = [
        container for container in containers
        if any(mount.get("Source") == str(volume(server)) for mount in container["Mounts"])
    ]
    if not matches:
        return None
    if len(matches) != 1:
        raise RuntimeError(f"Multiple containers use the server volume: {server}")
    data = matches[0]
    if not any(mount.get("Source") == str(volume(server)) and mount["Destination"] == "/home/container"
               and mount.get("RW") is True for mount in data["Mounts"]):
        raise RuntimeError(f"Unexpected volume mapping for {server}")
    networks = data["NetworkSettings"]["Networks"]
    if "pelican_nw" not in networks:
        raise RuntimeError(f"Server is not connected to the Pelican network: {server}")
    network = json.loads(common.output(["docker", "network", "inspect", "pelican_nw"]))[0]
    if not any(item.get("Gateway") == "172.18.0.1" for item in network["IPAM"]["Config"]):
        raise RuntimeError(f"Unexpected database gateway for {server}")
    return data


def source_password():
    text = SOURCE_CONFIG.read_text()
    password = re.search(r"(?m)^  password: '([A-Za-z0-9_-]+)'$", text)
    if password is None:
        raise RuntimeError("The working Velocity PostgreSQL config has an unexpected credential format.")
    if single.rewritten_config(text, password[1]) != text:
        raise RuntimeError("The source config is not the expected working PostgreSQL configuration.")
    return password[1]


def parse_h2(text):
    result = {}
    table = None
    fields = []
    for line in text.splitlines():
        parts = line.split("\t")
        if parts[0] == "TABLE":
            table, *fields = parts[1:]
            if table in result:
                raise RuntimeError("Duplicate H2 table.")
            result[table] = []
        elif parts[0] == "ROW" and table:
            if len(parts) - 1 != len(fields):
                raise RuntimeError("H2 row width mismatch.")
            row = {
                key: None if value == "!" else base64.b64decode(value, validate=True).decode()
                for key, value in zip(fields, parts[1:])
            }
            for key in ("id", "time", "expiry"):
                if key in row and row[key] is not None:
                    row[key] = int(row[key])
            if "value" in row:
                if row["value"] not in ("TRUE", "FALSE", "true", "false"):
                    raise RuntimeError("Unexpected H2 permission boolean.")
                row["value"] = row["value"].lower() == "true"
            result[table].append(row)
        else:
            raise RuntimeError("Unexpected H2 exporter output.")
    common.assert_equal(single.TABLES, set(result), "H2 table set")
    return result


def read_h2(root):
    source = volume(H2_SERVER) / "plugins/LuckPerms"
    target = root / "h2-copy"
    target.mkdir(mode=0o700)
    shutil.copyfile(source / "luckperms-h2-v2.mv.db", target / "luckperms-h2-v2.mv.db")
    result = common.output([
        "java", "--class-path", str(source / "libs/h2-driver-2.1.214.jar"),
        str(Path(__file__).with_name("LuckPermsH2Export.java")),
        str(target / "luckperms-h2-v2"),
    ])
    data = parse_h2(result)
    common.save_json(root / "h2-rows.json", data)
    return data


def read_postgres():
    return {
        table: [json.loads(row) for row in common.postgres_query(single.DATABASE, f"""
            SELECT row_to_json(t) FROM {common.identifier(table)} t;
        """).splitlines()]
        for table in sorted(single.TABLES)
    }


def stable(row):
    return json.dumps(row, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def permission_key(row):
    owner = "uuid" if "uuid" in row else "name"
    return (row[owner], row["permission"], row["server"], row["world"],
            stable(json.loads(row["contexts"])))


def comparable(row):
    content = {key: value for key, value in row.items() if key != "id"}
    for key in ("contexts", "groups"):
        if key in content:
            content[key] = json.loads(content[key])
    return content


def merge_plan(existing, incoming):
    additions = {}
    conflicts = []
    for table in sorted(single.TABLES):
        current = existing[table]
        local = incoming[table]
        if table == "luckperms_actions":
            counts = Counter(stable({k: v for k, v in row.items() if k != "id"}) for row in current)
            added = []
            for row in local:
                content = {k: v for k, v in row.items() if k != "id"}
                key = stable(content)
                if counts[key]:
                    counts[key] -= 1
                else:
                    added.append(content)
            additions[table] = added
            continue
        if table.endswith("_permissions"):
            key_for = permission_key
        elif table == "luckperms_players":
            key_for = lambda row: row["uuid"]
        else:
            key_for = lambda row: row["name"]
        index = {}
        for row in current:
            index.setdefault(key_for(row), []).append(row)
        added = []
        for row in local:
            key = key_for(row)
            content = {k: v for k, v in row.items() if k != "id"}
            matches = index.get(key, [])
            if not matches:
                added.append(content)
                index[key] = [row]
            elif any(comparable(match) == comparable(row) for match in matches):
                continue
            else:
                conflicts.append({"table": table, "existing": matches, "incoming": row})
        additions[table] = added
    return additions, conflicts


def assert_stopped():
    for server in SERVERS:
        container = inspect(server)
        if container is not None and container["State"]["Running"]:
            raise RuntimeError(f"Target {server} is running; stop it in Panel before this offline cutover.")


def merge_sql(current, additions):
    statements = [
        "BEGIN;", "SET LOCAL lock_timeout='10s';", "SET LOCAL statement_timeout='60s';",
        "SET LOCAL standard_conforming_strings=on;",
        "LOCK TABLE " + ", ".join(common.identifier(table) for table in sorted(single.TABLES))
        + " IN EXCLUSIVE MODE;",
    ]
    for table in sorted(single.TABLES):
        name = common.identifier(table)
        expected = common.identifier("expected_" + table)
        planned = common.identifier("planned_" + table)
        snapshot = common.literal(stable(current[table]))
        statements.append(f"""
            CREATE TEMP TABLE {planned} ON COMMIT DROP AS
                SELECT value FROM jsonb_array_elements({snapshot}::jsonb);
            DO $check$ BEGIN
                IF EXISTS (
                    (SELECT row_to_json(t)::jsonb FROM {name} t
                     EXCEPT ALL SELECT value FROM {planned})
                    UNION ALL
                    (SELECT value FROM {planned}
                     EXCEPT ALL SELECT row_to_json(t)::jsonb FROM {name} t)
                ) THEN
                    RAISE EXCEPTION 'Database changed since planning: {table}';
                END IF;
            END $check$;
            CREATE TEMP TABLE {expected} ON COMMIT DROP AS SELECT * FROM {name};
        """)
        for row in additions[table]:
            columns = ", ".join(common.identifier(key) for key in row)
            values = ", ".join(
                "NULL" if value is None else
                "TRUE" if value is True else "FALSE" if value is False else
                common.literal(str(value)) for value in row.values()
            )
            statements.append(f"""
                WITH inserted AS (
                    INSERT INTO {name} ({columns}) VALUES ({values}) RETURNING *
                ) INSERT INTO {expected} SELECT * FROM inserted;
            """)
        statements.append(f"""
            DO $check$ BEGIN
                IF EXISTS (
                    (SELECT * FROM {name} EXCEPT ALL SELECT * FROM {expected})
                    UNION ALL (SELECT * FROM {expected} EXCEPT ALL SELECT * FROM {name})
                ) THEN
                    RAISE EXCEPTION 'Post-merge verification failed: {table}';
                END IF;
            END $check$;
        """)
    return "\n".join([*statements, "COMMIT;"])


def verify_connection(password):
    result = common.output([
        "psql", "-X", "-qAt", "-w", "-v", "ON_ERROR_STOP=1",
        "-h", "172.18.0.1", "-U", single.DATABASE, "-d", single.DATABASE,
        "-c", "SELECT current_user;",
    ], env={**os.environ, "PGPASSWORD": password, "PGCONNECT_TIMEOUT": "5"})
    common.assert_equal(single.DATABASE, result.strip(), "bridge PostgreSQL authentication")


def replace_config(path, original, rewritten):
    if path.is_symlink() or path.read_text() != original:
        raise RuntimeError(f"Config changed during cutover or is a symlink: {path}")
    metadata = path.stat()
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".luckperms-", delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(rewritten)
            stream.flush()
            os.fchmod(stream.fileno(), 0o640)
            os.fchown(stream.fileno(), metadata.st_uid, metadata.st_gid)
            os.fsync(stream.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)
    directory = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def apply(root):
    assert_stopped()
    password = source_password()
    verify_connection(password)
    originals = {server: config(server).read_text() for server in SERVERS}
    rewritten = {server: single.rewritten_config(text, password) for server, text in originals.items()}
    if any(config(server).is_symlink() for server in SERVERS):
        raise RuntimeError("Refusing to replace a symlinked LuckPerms config.")
    root.mkdir(mode=0o700, parents=True, exist_ok=False)
    print(f"Private cutover backup: {root}", flush=True)
    for server, text in originals.items():
        (root / f"{server}-config-before.yml").write_text(text)
    local = read_h2(root)
    assert_stopped()
    current = read_postgres()
    additions, conflicts = merge_plan(current, local)
    common.save_json(root / "merge-plan.json", {"additions": additions, "conflicts": conflicts})
    if any(conflict["table"] != "luckperms_players" for conflict in conflicts):
        raise RuntimeError("New permission/track conflicts found; refusing the merge. Inspect the private plan.")
    with (root / "postgres-before.dump").open("xb") as stream:
        common.run(["runuser", "-u", "postgres", "--", "pg_dump", "--format=custom",
                    "--dbname", single.DATABASE], stdout=stream, text=False)
    state = {"stage": "merging", "kept_shared_player_records": len(conflicts)}
    common.save_json(root / "state.json", state)
    assert_stopped()
    common.postgres_query(single.DATABASE, merge_sql(current, additions))
    state["stage"] = "configuring"
    common.save_json(root / "state.json", state)
    for server in SERVERS:
        assert_stopped()
        replace_config(config(server), originals[server], rewritten[server])
        common.assert_equal(rewritten[server], config(server).read_text(), f"{server} PostgreSQL config")
        common.assert_equal(0o640, config(server).stat().st_mode & 0o777, f"{server} config mode")
    verify_connection(password)
    assert_stopped()
    state["stage"] = "complete"
    common.save_json(root / "state.json", state)
    for table in sorted(single.TABLES):
        print(f"{table}: added {len(additions[table])} rows", flush=True)
    print(f"Kept {len(conflicts)} conflicting shared player records.", flush=True)
    print("All four PostgreSQL configs verified. No target containers were started.", flush=True)
    print("Run 'lpv sync' in the running Velocity console to refresh its cached permissions.", flush=True)


def audit(root):
    source_password()
    for server in SERVERS:
        if inspect(server) is None:
            print(f"No existing container for {server}; it will remain unstarted.", flush=True)
        single.rewritten_config(config(server).read_text(), "validation_only")
    root.mkdir(mode=0o700, parents=True, exist_ok=False)
    print(f"Private audit and backups: {root}", flush=True)
    container = inspect(H2_SERVER)
    was_running = container is not None and container["State"]["Running"]
    if was_running:
        common.run(["docker", "stop", "--timeout", "60", container["Id"]])
    try:
        state = inspect(H2_SERVER)
        if state is not None and state["State"]["Running"]:
            raise RuntimeError("H2 server is running; refusing to copy its live database.")
        local = read_h2(root)
        state = inspect(H2_SERVER)
        if state is not None and state["State"]["Running"]:
            raise RuntimeError("H2 server restarted during the audit; discard this copy and retry.")
    finally:
        if was_running:
            state = inspect(H2_SERVER)
            if state is None or state["Id"] != container["Id"]:
                raise RuntimeError("H2 container changed during the audit; restore its running state in Panel.")
            if not state["State"]["Running"]:
                common.run(["docker", "start", container["Id"]])
    current = read_postgres()
    common.save_json(root / "postgres-rows.json", current)
    additions, conflicts = merge_plan(current, local)
    common.save_json(root / "merge-plan.json", {"additions": additions, "conflicts": conflicts})
    for table in sorted(single.TABLES):
        count = sum(conflict["table"] == table for conflict in conflicts)
        print(f"{table}: PostgreSQL={len(current[table])}, H2={len(local[table])}, "
              f"new={len(additions[table])}, conflicts={count}", flush=True)
    print("Audit only: live PostgreSQL and all plugin configurations remain unchanged.", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Audit/merge additional LuckPerms servers into shared PostgreSQL.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--audit", action="store_true")
    mode.add_argument("--apply", action="store_true")
    parser.add_argument("--keep-shared-players", action="store_true")
    args = parser.parse_args()
    if args.apply and not args.keep_shared_players:
        parser.error("--apply requires explicit --keep-shared-players conflict policy.")
    if os.geteuid() != 0:
        parser.error("Run with sudo.")
    os.umask(0o077)
    with Path("/run/lock/luckperms-servers.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        root = BACKUPS / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        if args.audit:
            audit(root)
        else:
            apply(root)


if __name__ == "__main__":
    main()
