# How to Backup / Export / Dump PostgreSQL Database

Two ways to back up a PostgreSQL database (structure + data) from the terminal, depending on whether the Postgres port is reachable directly from your machine or only via SSH.

## Prerequisites

- `postgresql-client` (`pg_dump`, `pg_dumpall`, `psql`) installed locally and/or on the DB host.
- Credentials for the target database (host, port, username, password).
- If the password contains shell-special characters (e.g. `!`, `@`, `#`), always wrap it in **single quotes** on the command line, or better, use the `~/.pgpass` method described below to avoid typing it at all.

## Option A — Dump directly from your local machine

Use this when the Postgres port (default `5432`) is reachable directly from your laptop.

```bash
# Structure + data, compressed custom format (recommended — supports selective pg_restore)
PGPASSWORD='your_password' pg_dump \
  -h <db_host> -p 5432 -U <username> -d <dbname> \
  -Fc -f "backup_$(date +%Y%m%d_%H%M%S).dump"

# Plain-text SQL (human-readable/editable)
PGPASSWORD='your_password' pg_dump \
  -h <db_host> -p 5432 -U <username> -d <dbname> \
  > "backup_$(date +%Y%m%d_%H%M%S).sql"

# All databases + roles/grants
PGPASSWORD='your_password' pg_dumpall \
  -h <db_host> -p 5432 -U <username> \
  > "backup_all_$(date +%Y%m%d_%H%M%S).sql"
```

No download step is needed — the dump file is already on your local machine.

## Option B — Dump on the DB host, then download

Use this when `5432` is not exposed to your laptop and the DB host is only reachable via SSH.

```bash
# 1. Run pg_dump on the remote host
ssh <ssh_user>@<db_host> \
  "PGPASSWORD='your_password' pg_dump -h localhost -U <username> -d <dbname> -Fc -f /tmp/backup.dump"

# 2. Download the dump file to your local machine
scp <ssh_user>@<db_host>:/tmp/backup.dump ./backup.dump

# 3. Clean up the remote temp file once the local copy is confirmed
ssh <ssh_user>@<db_host> "rm /tmp/backup.dump"
```

## Database vs. schema

A Postgres server can host multiple **databases** (what you connect to with `-d`); each database can contain multiple **schemas** (namespaces inside that database, e.g. `public`). Don't assume every name you've heard is a database — check first:

```bash
# List databases on the server
PGPASSWORD='your_password' psql -h <db_host> -p 5432 -U <username> -d postgres -c "\l"

# List schemas inside a specific database
PGPASSWORD='your_password' psql -h <db_host> -p 5432 -U <username> -d <dbname> -c "\dn"
```

## Backing up a specific schema

To back up one (or a few) schemas instead of the whole database, add `-n <schema>` to `pg_dump` (repeatable for multiple schemas). This still requires `-d <dbname>` — a schema always lives inside one database.

```bash
# Single schema
PGPASSWORD='your_password' pg_dump \
  -h <db_host> -p 5432 -U <username> -d <dbname> \
  -n <schema_name> \
  -Fc -f "<schema_name>_$(date +%Y%m%d_%H%M%S).dump"

# Multiple schemas in one dump
PGPASSWORD='your_password' pg_dump \
  -h <db_host> -p 5432 -U <username> -d <dbname> \
  -n <schema_one> -n <schema_two> \
  -Fc -f "schemas_$(date +%Y%m%d_%H%M%S).dump"

# All schemas except one (e.g. skip pgbouncer's internal schema)
PGPASSWORD='your_password' pg_dump \
  -h <db_host> -p 5432 -U <username> -d <dbname> \
  -N pgbouncer \
  -Fc -f "<dbname>_no_pgbouncer_$(date +%Y%m%d_%H%M%S).dump"
```

## Safer password handling with `~/.pgpass`

Instead of passing `PGPASSWORD` on the command line (which can leak into shell history/process lists), create a `.pgpass` file:

```
# ~/.pgpass  (format: host:port:database:username:password)
<db_host>:5432:*:<username>:your_password
```

```bash
chmod 600 ~/.pgpass
```

With this in place, `pg_dump`/`psql` will pick up the password automatically — drop `PGPASSWORD=...` from the commands above.

## Troubleshooting: "Invalid username/password,login denied" with `PGPASSWORD`

If `pg_dump`/`psql` rejects a password you know is correct, and that password contains shell-special characters (`!`, `@`, `#`, `$`, etc.), the shell is probably mangling it before it reaches Postgres:

- **Double quotes don't protect `!`** — in bash/zsh, `PGPASSWORD="pwFoo123!@#"` triggers history expansion on the `!` and silently corrupts the value. Always use **single quotes**: `PGPASSWORD='pwFoo123!@#'`.
- Copy-pasting into a command can also drop/alter characters — re-typing or re-copying the password is worth trying before assuming the credential itself is wrong.

The most reliable fix is to stop passing `PGPASSWORD` on the command line at all and rely on `~/.pgpass` (above) — once it's set up correctly (`chmod 600`, correct `host:port:database:username:password` line), just drop `PGPASSWORD=...` entirely:

```bash
pg_dump \
  -h <db_host> -p 5432 -U <username> -d <dbname> \
  -n <schema_name> \
  -Fc -f "<schema_name>_$(date +%Y%m%d_%H%M%S).dump"
```

`pg_dump`/`psql` will look up the password from `.pgpass` automatically, matching on host/port/database/user — no quoting pitfalls possible.

## Restoring a backup

```bash
# Custom format (-Fc)
pg_restore -h <db_host> -U <username> -d <dbname> backup.dump

# Plain SQL
psql -h <db_host> -U <username> -d <dbname> -f backup.sql

# Restore only a specific schema from a custom-format dump that contains more than one
pg_restore -h <db_host> -U <username> -d <dbname> -n <schema_name> backup.dump
```
