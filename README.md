# Shared Local Infrastructure (Docker Compose)

A single, reusable local infrastructure stack for **MariaDB**, **PostgreSQL**, **MongoDB**, **Redis**, **RabbitMQ**, and **KrakenD**, meant to be shared across every host-native service on this machine:

- Go services in `~/Workspaces/go/*`
- NestJS services in `~/Workspaces/node/*`
- KrakenD gateway templates in `~/Workspaces/templates/*`
- This runtime, `~/._infra-docker`

Instead of every service repo bundling its own Postgres/Redis/etc. containers, they all connect to `127.0.0.1:<port>` and share one long-lived stack. Runs on macOS (incl. Apple Silicon) and Linux.

## Goal

Give host-native microservices a consistent, disposable, and shareable data/messaging/gateway layer for local development — one `docker compose up -d`, predictable ports, persisted data, and health-gated startup so dependent services never race an unready database.

## Directory Layout

```text
._infra-docker/
├── README.md
├── .env.example          # committed template — copy to .env
├── .env                  # actual secrets/config — gitignored, not committed
├── .gitignore
├── docker-compose.yml     # the whole stack definition
├── mongo/
│   └── init/
│       └── 01-init.js     # creates an app-level Mongo user on first boot
├── data/                  # bind-mounted persistence — gitignored
│   ├── mariadb/
│   ├── postgres/
│   ├── mongodb/
│   ├── redis/
│   ├── rabbitmq/
│   ├── portainer/
│   ├── redisinsight/
│   ├── pgadmin/
│   └── cloudbeaver/
└── docs/
```

`data/` holds all container state on the host filesystem. Removing a subfolder (or `docker compose down -v`) wipes that service back to a fresh install.

## Services

| Service    | Image                     | Container         | Host Port(s)                 | Purpose |
|------------|---------------------------|--------------------|-------------------------------|---------|
| mariadb    | `mariadb:11.4`            | `infra-mariadb`    | `3306`                        | MySQL-compatible relational DB, `utf8mb4` by default |
| postgres   | `postgres:17-alpine`      | `infra-postgres`   | `5432`                        | Relational DB |
| mongodb    | `mongo:8`                 | `infra-mongodb`    | `27017`                       | Document DB, runs `mongo/init/01-init.js` on first boot |
| redis      | `redis:8-alpine`          | `infra-redis`      | `6379`                        | Cache/queue, AOF persistence + password auth |
| rabbitmq   | `rabbitmq:4-management`   | `infra-rabbitmq`   | `5672` (AMQP), `15672` (mgmt UI) | Message broker + management dashboard |
| krakend    | `devopsfaith/krakend:2.7` | `infra-krakend`    | `8088` (→ container `8080`)   | API gateway, proxies to host-native services |
| portainer  | `portainer/portainer-ce:lts` | `infra-portainer` | `9000` (HTTP UI), `9443` (HTTPS UI), `8000` (Edge tunnel) | Docker management UI — local containers by default, plus remote environments via Edge Agent |
| redisinsight | `redis/redisinsight:latest` | `infra-redisinsight` | `5540` (→ container `5540`) | Web GUI for browsing/managing Redis |
| mongo-express | `mongo-express:1-20-alpine3.19` | `infra-mongo-express` | `8081` (→ container `8081`) | Web GUI for browsing/managing MongoDB, pre-wired to the `mongodb` service |
| pgadmin    | `dpage/pgadmin4:latest`   | `infra-pgadmin`    | `5050` (→ container `80`)     | Web GUI for browsing/managing PostgreSQL |
| cloudbeaver | `dbeaver/cloudbeaver:latest` | `infra-cloudbeaver` | `8978` (→ container `8978`) | Universal DB manager (SQL editor/browser) for Postgres, MariaDB, MongoDB — handy for MariaDB, which has no dedicated GUI here |

All services join a single bridge network, `infra_net`. The compose project is named `shared-local-infra`, set both via the top-level `name:` field and via `COMPOSE_PROJECT_NAME` in `.env` — the two are kept in sync deliberately, since `COMPOSE_PROJECT_NAME` actually takes precedence over the top-level `name:` field when both are present (not the other way around), and a mismatch here would silently make Compose manage a different project than the file describes.

`krakend` waits on `service_healthy` for all five data/messaging services before starting, so it never boots ahead of dependencies it might proxy to.

## Prerequisites

- Docker Desktop (macOS) or Docker Engine 20.10+ with the `compose` plugin (Linux)
- A KrakenD config directory somewhere on disk containing a `krakend.json` (see [KrakenD Gateway](#krakend-gateway) below)

## Setup

Steps 1 (`make env`), 3–4 (`make bootstrap`), and 5 (`make up`) below can be run via the `Makefile` — see [Day-2 Operations](#day-2-operations).

1. Copy the env template and fill in real values:

   ```bash
   cd ~/._infra-docker
   cp .env.example .env
   ```

2. Point `KRAKEND_CONFIG_DIR` in `.env` at a folder containing `krakend.json`:

   ```dotenv
   KRAKEND_CONFIG_DIR=/Users/teguhpratama/Workspaces/templates/shared-infra-gateway
   ```

   If your gateway template builds to `dist/krakend.json` (e.g. `paycloud-apigateway`, `paycloud-apigatewayft`), point at that `dist` folder instead. See [KrakenD Gateway](#krakend-gateway) for why the bundled production configs in those repos won't work here as-is.

3. Data directories are created automatically by Docker on first `up`, but you can pre-create them:

   ```bash
   mkdir -p ~/._infra-docker/data/{mariadb,postgres,mongodb,redis,rabbitmq,redisinsight,pgadmin,cloudbeaver}
   ```

4. **Linux only** — normalize bind-mount ownership:

   ```bash
   cd ~/._infra-docker
   sudo chown -R $(id -u):$(id -g) data
   ```

5. Start the stack:

   ```bash
   cd ~/._infra-docker
   docker compose --env-file .env up -d
   docker compose ps
   ```

6. Smoke check:

   ```bash
   curl -i http://localhost:8088/__health
   docker compose logs --tail=50 krakend
   ```

   Expect all containers `Up (healthy)` and a `200 OK` with `{"status":"ok"}` from KrakenD's own health endpoint.

## Environment Variables (`.env`)

`.env.example` is the committed template; `.env` is the real, gitignored file each machine customizes.

| Variable | Default | Notes |
|---|---|---|
| `COMPOSE_PROJECT_NAME` | `shared-local-infra` | Takes precedence over `docker-compose.yml`'s top-level `name:` field — kept identical to it so the project name is unambiguous |
| `MARIADB_PORT` | `3306` | Host port |
| `POSTGRES_PORT` | `5432` | Host port |
| `MONGODB_PORT` | `27017` | Host port |
| `REDIS_PORT` | `6379` | Host port |
| `RABBITMQ_AMQP_PORT` | `5672` | Host port for AMQP |
| `RABBITMQ_MGMT_PORT` | `15672` | Host port for the management UI |
| `KRAKEND_PORT` | `8088` | Host port; **do not** pass this into the krakend container's env — see [Gotcha #2](#gotcha-2-krakend_port-collision) |
| `PORTAINER_PORT` / `PORTAINER_HTTPS_PORT` / `PORTAINER_EDGE_PORT` | `9000` / `9443` / `8000` | Host ports |
| `REDISINSIGHT_PORT` | `5540` | Host port for the RedisInsight web UI |
| `MONGO_EXPRESS_PORT` | `8081` | Host port for the Mongo Express web UI |
| `PGADMIN_PORT` | `5050` | Host port for the pgAdmin web UI (maps to container port `80`) |
| `CLOUDBEAVER_PORT` | `8978` | Host port for the CloudBeaver web UI |
| `MONGO_EXPRESS_USERNAME` / `MONGO_EXPRESS_PASSWORD` | — | HTTP basic-auth credentials guarding the Mongo Express web UI (separate from the Mongo root user, which it uses internally to connect) |
| `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD` | — | Login credentials for the pgAdmin web UI |
| `MARIADB_ROOT_PASSWORD` / `MARIADB_DATABASE` / `MARIADB_USER` / `MARIADB_PASSWORD` | — | MariaDB credentials/schema |
| `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | — | Postgres credentials/schema |
| `POSTGRES_PLATFORM` | *(empty)* | Only set to `linux/amd64` if you hit arch-specific plugin issues on Apple Silicon; currently unused by the compose file (commented out) |
| `MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD` / `MONGO_INITDB_DATABASE` | — | Mongo root credentials + default DB |
| `MONGO_APP_USERNAME` / `MONGO_APP_PASSWORD` | — | Consumed by `mongo/init/01-init.js` to create a non-root app user |
| `REDIS_PASSWORD` | — | Passed via `--requirepass` |
| `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` / `RABBITMQ_DEFAULT_VHOST` | — | RabbitMQ credentials/vhost |
| `KRAKEND_CONFIG_DIR` | — | **Absolute host path** to the folder containing `krakend.json`; bind-mounted read-only to `/etc/krakend` |
| `HOST_SERVICE_BASE_URL` | `http://host.docker.internal:3000` | Reference value for the base URL of the host-native service KrakenD proxies to in the sample config |

Never commit `.env` — only `.env.example`. Both `.env` and `data/` are in `.gitignore`.

## KrakenD Gateway

KrakenD does not bundle its own routes — it reads whatever `krakend.json` lives in `KRAKEND_CONFIG_DIR`, mounted read-only at `/etc/krakend` in the container.

A generic working sample lives at `~/Workspaces/templates/shared-infra-gateway/krakend.json`:

```json
{
  "$schema": "https://www.krakend.io/schema/v2.7/krakend.json",
  "version": 3,
  "name": "local-shared-gateway",
  "timeout": "3000ms",
  "cache_ttl": "300s",
  "output_encoding": "json",
  "port": 8080,
  "endpoints": [
    {
      "endpoint": "/api/health",
      "method": "GET",
      "backend": [{ "host": ["http://host.docker.internal:3000"], "url_pattern": "/health" }]
    },
    {
      "endpoint": "/api/users/{id}",
      "method": "GET",
      "backend": [{ "host": ["http://host.docker.internal:3000"], "url_pattern": "/users/{id}" }]
    }
  ]
}
```

- `host.docker.internal` is how the gateway reaches host-native services (Go/NestJS apps running outside Docker). Docker Desktop provides this by default; on Linux it's enabled via the compose file's `extra_hosts: host.docker.internal:host-gateway`.
- The `/api/health` endpoint proxies to your host service's `/health` — update the host/port to match whatever you're running on `3000` (or another port).
- KrakenD reserves `/__health` as its **own** built-in health endpoint (`{"status":"ok"}`, gateway-only, no backend call). Do not redefine `/__health` as a custom endpoint — see [Gotcha #1](#gotcha-1-__health-is-reserved).

`paycloud-apigateway/dist/krakend.json` and `paycloud-apigatewayft/dist/krakend.json` also exist in `~/Workspaces/templates/`, but they are **real production configs** — they listen on port `30001` (not `8080`) and proxy to internal Docker service hostnames like `pjp-be-clientpg-manager:9141` that don't exist on this isolated `infra_net` network. Pointing `KRAKEND_CONFIG_DIR` at either of those `dist` folders as-is will make KrakenD parse successfully but fail almost every route (and the health check will hit the wrong internal port). Only use them if you first adapt the `port` and backend hosts for this stack.

## Verification Commands

Run from `~/._infra-docker` after `docker compose up -d`. Load `.env` into the shell first for convenience:

```bash
cd ~/._infra-docker
set -a; source .env; set +a
```

**Global**
```bash
docker compose ps
```

**MariaDB** — expect `mysqld is alive`
```bash
docker compose exec mariadb mariadb-admin -uroot -p"$MARIADB_ROOT_PASSWORD" ping
```

**PostgreSQL** — expect `accepting connections`
```bash
docker compose exec postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

**MongoDB** — expect `{ ok: 1 }`
```bash
docker compose exec mongodb mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval 'db.adminCommand({ ping: 1 })'
```

**Redis** — expect `PONG`
```bash
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" ping
```

**RabbitMQ** — expect a JSON payload with `rabbitmq_version`
```bash
curl -u "$RABBITMQ_DEFAULT_USER:$RABBITMQ_DEFAULT_PASS" http://localhost:${RABBITMQ_MGMT_PORT}/api/overview
```

Management UI: `http://localhost:${RABBITMQ_MGMT_PORT}` (login with the same credentials).

**KrakenD** — expect `200 OK`, `{"status":"ok"}`
```bash
curl -i "http://localhost:${KRAKEND_PORT}/__health"
```

## Connecting Host-Native Services

From Go/NestJS apps running directly on the host (not in Docker):

| Target | Address |
|---|---|
| MariaDB | `127.0.0.1:${MARIADB_PORT}` |
| PostgreSQL | `127.0.0.1:${POSTGRES_PORT}` |
| MongoDB | `127.0.0.1:${MONGODB_PORT}` |
| Redis | `127.0.0.1:${REDIS_PORT}` |
| RabbitMQ | `127.0.0.1:${RABBITMQ_AMQP_PORT}` |

For KrakenD to reach *your* host-native service, reference it in `krakend.json` as `http://host.docker.internal:<your-host-port>`.

## Portainer

Local Portainer instance for browsing containers/logs. It auto-manages this machine's Docker Engine (via the bind-mounted `/var/run/docker.sock`) as its default "local" environment — no extra setup needed to see the stack above in the UI.

**First-time setup:**

```bash
open http://localhost:${PORTAINER_PORT}   # or the HTTPS port, self-signed cert
```

Create the admin account on first visit (Portainer disables itself if left unconfigured for too long — don't dawdle).

**Connecting a remote host you don't have inbound access to** (e.g. a VM behind a firewall, like `pjp-app-adminftapi`'s host): use an **Edge Agent** environment rather than the standard Agent — the remote side initiates the connection *out* to this Portainer instance on `PORTAINER_EDGE_PORT` (`8000`), so nothing needs to be reachable inbound on the remote VM.

1. In the Portainer UI: **Environments → Add environment → Edge Agent**.
2. Portainer generates a join token/command for the remote host to run (typically a `docker run portainer/agent:lts` one-liner with the edge key baked in).
3. Hand that command to whoever has access to the remote host (devops) to run there — they don't need any other credentials from you, and you don't need SSH access to their host.
4. Once the remote agent checks in, the environment shows up in Portainer's environment list; browse its containers/logs from here like any local one.

This machine must stay reachable from the remote host on `PORTAINER_EDGE_PORT` for the tunnel to establish (may need a port-forward/tunnel depending on network topology — that's a devops-side detail, not a compose-file concern).

## Database & Cache GUIs

Four local-only admin UIs, one per data store (plus a universal one for MariaDB). None of them are exposed beyond `127.0.0.1` unless you change the port bindings.

**RedisInsight** — `http://localhost:${REDISINSIGHT_PORT}`
No login. On first visit, add a connection with host `redis`, port `6379`, and the password from `REDIS_PASSWORD` (containers reach each other by service name over `infra_net`).

**Mongo Express** — `http://localhost:${MONGO_EXPRESS_PORT}`
HTTP basic-auth login using `MONGO_EXPRESS_USERNAME` / `MONGO_EXPRESS_PASSWORD`. Already pre-wired to the `mongodb` service via its root credentials — no manual connection setup needed.

**pgAdmin** — `http://localhost:${PGADMIN_PORT}`
Log in with `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD`. Register a new server pointing at host `postgres`, port `5432`, using `POSTGRES_USER` / `POSTGRES_PASSWORD`.

**CloudBeaver** — `http://localhost:${CLOUDBEAVER_PORT}`
Create the admin account on first visit (same pattern as Portainer — don't leave it unconfigured for long). Add connections using the in-network hostnames: `postgres:5432`, `mariadb:3306`, or `mongodb:27017`, with the matching credentials from `.env`.

## Day-2 Operations

A `Makefile` wraps the commands below — run `make help` for the full list (`make up`, `make down`, `make restart SERVICE=postgres`, `make logs SERVICE=krakend`, `make check`, `make urls`, etc.). The raw commands still work directly and are documented here for reference:

```bash
# Start
docker compose --env-file .env up -d

# Stop, keep data
docker compose down

# Stop and wipe all volumes (destructive)
docker compose down -v

# Restart a single component
docker compose restart postgres

# Tail one service's logs
docker compose logs -f krakend

# Tail everything
docker compose logs -f --tail=100
```

## Known Gotchas

These were hit and fixed while first bringing this stack up — documented so they don't get relitigated.

### Gotcha #1: `/__health` is reserved

KrakenD 2.7.2 treats `/__health` as a **built-in, reserved** endpoint. Defining a custom endpoint at that exact path is rejected outright (`ERROR parsing the configuration file: ... ignoring the 'GET /__health' endpoint, since it is invalid!!!`) and the container crash-loops. If you want a backend-proxied health check *in addition to* KrakenD's own, use a different path — this stack uses `/api/health`.

### Gotcha #2: `KRAKEND_PORT` collision

The KrakenD CLI auto-binds environment variables to its own flags (via Viper), and `--port` binds to `KRAKEND_PORT`. If the krakend service is given `env_file: .env` (which defines `KRAKEND_PORT=8088` as the *host* port for the compose port mapping), KrakenD silently listens on `8088` **inside** the container instead of the `8080` set in `krakend.json` — breaking the `8088:8080` port mapping with `connection reset by peer`, since nothing listens on 8080 anymore.

Fix: the `krakend` service in `docker-compose.yml` intentionally does **not** use `env_file: .env`. It doesn't need any of the app secrets, and this avoids the collision entirely.

### Gotcha #3: wrong KrakenD image name

`krakend/krakend-ce` does not exist on Docker Hub (`pull access denied`). The correct image is `devopsfaith/krakend`. `docker-compose.yml` is already pinned to `devopsfaith/krakend:2.7` (KrakenD v2.7.2).

## Operational Notes

- Keep all shared infra in this one compose project to avoid port/naming drift across service repos.
- `data/` is bind-mounted for predictable, inspectable, easy-to-wipe persistence — avoid switching to named volumes unless you have a specific reason.
- If a DB container keeps failing to start on Linux, check `data/` ownership (see Setup step 4) before anything else.
- Dependent services are gated on `service_healthy`, not fixed sleeps — if you add a new service that depends on one of these, prefer the same pattern over a sleep/retry loop in application code.
