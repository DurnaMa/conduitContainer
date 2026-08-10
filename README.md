# Conduit Container

This repository containerizes the RealWorld "Conduit" application: an Angular frontend, a Django REST backend and a PostgreSQL database, orchestrated with Docker Compose. Adminer is included as an optional database UI.

The application source (`conduit-frontend`, `conduit-backend`) is vendored unmodified on `main`; all container and configuration work is kept in separate commits on top of it.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Command conventions](#command-conventions)
- [Quickstart](#quickstart)
- [Files](#files)
- [Architecture](#architecture)
- [Access](#access)
- [Usage](#usage)
  - [Configuration](#configuration)
  - [Build time vs. runtime](#build-time-vs-runtime)
  - [Creating an admin user](#creating-an-admin-user)
  - [Verify](#verify)
  - [Logs](#logs)
  - [Stop and Cleanup](#stop-and-cleanup)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Docker installed — check with: `docker -v`
- Docker Compose installed — check with: `docker compose version`
- Host ports — default to `8282`, `8283` and `8285`; change them in `.env` if they are taken.
- A `.env` file — created in the Quickstart below.

The stack runs on any Docker host: Windows or macOS with Docker Desktop, or Linux with Docker Engine.
It does not require a remote server — running it locally works as long as the host and origin variables match the address you use (see [Configuration](#configuration)).
If you run it on a remote machine, replace `localhost` with that machine's IP address everywhere below and make sure the ports are reachable through its firewall or security group.

## Command conventions

All commands are written to run as shown in **Terminal on macOS** and **bash on Linux**. Where a command has no cross-platform form, both variants are given side by side.

> [!NOTE]
> On Linux, Docker commands need root unless your user is in the `docker` group.
> Either add yourself to it once with `sudo usermod -aG docker $USER` (log out and back in afterwards), or prefix every `docker` command below with `sudo`.
> On Windows and macOS with Docker Desktop, no prefix is needed.

## Quickstart

1. Clone the repository:

   ```bash
   git clone https://github.com/DurnaMa/conduitContainer.git
   ```

2. Change into the project directory:

   ```bash
   cd conduitContainer
   ```

3. Copy the template:

   ```bash
   cp .env.example .env
   ```

4. Edit `.env` and fill in the empty values. Generate `SECRET_KEY` with:

   ```bash
   openssl rand -base64 48
   ```

> [!IMPORTANT]
> Avoid `$` in any value in `.env`. Docker Compose reads it as the start of a variable reference and the value arrives truncated.
> Base64 output never contains `$`. Where a `$` is unavoidable, write it as `$$`.

5. Build the images and start the containers:

   ```bash
   docker compose up -d --build
   ```

6. Open <http://localhost:8282> in your browser.

7. Create an admin user — see [Creating an admin user](#creating-an-admin-user).

## Files

| File | Purpose |
|---|---|
| `README.md` | This documentation |
| `docker-compose.yaml` | Defines the `frontend`, `backend`, `db` and `adminer` services, their ports, the `db` volume and all environment variables |
| `.env.example` | Template listing every variable the compose file references, without secret values |
| `.gitignore` | Keeps secrets (`.env`), build output and caches out of Git |
| `conduit-frontend/Dockerfile` | Multi-stage build: Angular build with Node, served by Nginx |
| `conduit-frontend/.dockerignore` | Excludes `node_modules` and build output from the frontend build context |
| `conduit-backend/Dockerfile` | Multi-stage build: pip install stage, then a slim runtime image running Gunicorn |
| `conduit-backend/.dockerignore` | Excludes caches and local files from the backend build context |
| `conduit-backend/entrypoint.sh` | Runs `migrate` on container start, then execs Gunicorn |

## Architecture

| Service | Image / Build | Host port | Container port |
|---|---|---|---|
| `frontend` | built from `./conduit-frontend` (Node build, `nginx:1.31.3-alpine` runtime) | `8282` | `80` |
| `backend` | built from `./conduit-backend` (`python:3.5.10-slim-buster`, Gunicorn) | `8283` | `80` |
| `db` | `postgres:18.4-alpine3.24` | *(none)* | `5432` |
| `adminer` | `adminer` | Host port (default) `8285` | Host port (default) `8080` |

The database deliberately has no host port. Only the backend reaches it, over the internal Docker network under the hostname `db`. All services use `restart: unless-stopped`.

> [!NOTE]
> Since PostgreSQL 18, `PGDATA` lives in `/var/lib/postgresql` instead of `/var/lib/postgresql/data`. The `db` volume is mounted accordingly.
> Using the older path with an 18.x image would silently leave the data unpersisted.


## Access

Ports shown are the defaults from `.env.example`. If you changed `PORTS_FRONTEND`
or `PORTS_BACKEND`, use those instead.

Replace `localhost` with the host's IP address if you are not running the stack on your own machine.

Adminer only listens on the VM's loopback interface. Open a tunnel first:

```bash
ssh -L 8285:127.0.0.1:8285 <user>@<VM-IP>
```

To log into Adminer, choose system **PostgreSQL**, server `db`, and use `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB` from your `.env`.

> [!NOTE]
> `http://localhost:8283/` returns `Not Found`. That is expected — the backend only defines `/admin/` and `/api/`.

## Usage

### Configuration

All configuration goes through `.env`. No values are hard-coded in the compose file, and no secrets belong in Git.

| Variable | Purpose | Example |
|---|---|---|
| `HOST` | Address the stack is reached under. Used to build the API URL, `ALLOWED_HOSTS` and the CORS origin | `localhost` |
| `PORTS_FRONTEND` | Host port the frontend is published on | `8282` |
| `PORTS_BACKEND` | Host port the backend is published on. Also becomes the port in the API URL | `8283` |
| `PORTS_ADMINER` | Host port Adminer is published on, bound to `127.0.0.1` only | `8285` |
| `SECRET_KEY` | Django secret used for signing sessions and tokens | *(blank — generate your own)* |
| `DEBUG` | Django debug mode. Leave off for anything but local debugging | `False` |
| `POSTGRES_DB` | Database name, used by both `db` and `backend` | `conduit` |
| `POSTGRES_USER` | Database user | `conduit` |
| `POSTGRES_PASSWORD` | Password for that user | *(blank — set your own)* |
| `DJANGO_SUPERUSER_PASSWORD` | Password used when the admin user is created | *(blank — set your own)* |

`API_URL`, `ALLOWED_HOSTS` and `CORS_ORIGIN_WHITELIST` are not set by hand.
The compose file builds them from `HOST` and the port variables, so a single
change to `HOST` or a port stays consistent across all three.

> [!IMPORTANT]
> A variable that is set but empty is not the same as a missing one. `os.environ.get('X', 'default')` returns an empty string for `X=`, not the default. An empty `SECRET_KEY` makes Django fail when it signs a session.

### Build time vs. runtime

Which variables take effect when decides whether a change needs a rebuild:

| Build time — needs `--build` | Runtime — recreating the container is enough |
|---|---|
| `API_URL` (compiled into the Angular bundle) | `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS`, `CORS_ORIGIN_WHITELIST`, `POSTGRES_*`, `DJANGO_SUPERUSER_PASSWORD` |

```bash
# after changing API_URL
docker compose up -d --build

# after changing any runtime variable
docker compose up -d
```

> [!IMPORTANT]
> The `environment:` block does not apply during `docker compose build`. Only the build `args` do. During the image build Django falls back to the defaults in `settings.py`, so those must be valid on their own or `collectstatic` fails.

Compose passes a service only what its own `environment:` block lists. Putting a variable in `.env` alone does not make it visible inside a container.

### Creating an admin user

The entrypoint runs migrations and starts Gunicorn; it does not create a user. Create one once, after the stack is up:

```bash
docker compose exec backend python manage.py createsuperuser
```

> [!IMPORTANT]
> This application's `create_superuser` ignores the password you type.
> It uses `DJANGO_SUPERUSER_PASSWORD` if that variable is at least four characters long, and falls back to a hard-coded default otherwise.
> Set the variable in `.env` and recreate the backend container *before* running the command — it only applies at the moment the user is created and does not change an existing one.

> [!IMPORTANT]
> The user model uses the email address as its login field. Log into `/admin/` with the email, not the username.

### Verify

1. Resolve the compose file against `.env` and check it is valid:

   > [!WARNING]
   > This prints all variables in plain text, passwords included. Do not run it in a shared screen recording.

   ```bash
   docker compose config
   ```

2. Check that all four containers are running:

   ```bash
   docker compose ps
   ```

3. Check what the backend actually received — more reliable than reading `.env`, which differs per machine:

   ```bash
   docker compose exec backend printenv
   ```

4. Call the API directly:

   ```bash
   curl -i http://localhost:8283/api/tags
   ```

   Expect status `200` and a `Server: gunicorn` response header. The header confirms a WSGI server is serving the app rather than a development server.

5. Open the frontend and navigate through it. In the browser's network tab, the requests must go to `http://localhost:8283/api/...`, not to `api.realworld.io`.

6. Confirm data persistence: create something in the admin, then run `docker compose down` followed by `docker compose up -d`. The record must still be there.

### Logs

```bash
# follow all services
docker compose logs -f

# a single service
docker compose logs -f backend
```

Write the logs of one container to a file:

```bash
docker logs conduit-backend-1 > container-logs.txt
```

### Stop and Cleanup

1. Stop and remove the containers, keeping the database volume:

   ```bash
   docker compose down
   ```

2. Remove containers **and** volumes:

   > [!WARNING]
   > This deletes the `db` volume. The database and everything in it are permanently gone, including the admin user.

   ```bash
   docker compose down -v
   ```

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Bad Request (400)` from Django | The host you are using is not in `ALLOWED_HOSTS`. Django compares the hostname without the port. |
| `Welcome to nginx!` instead of the app | `index.html` is not directly in `/usr/share/nginx/html`. Check the `COPY` path in the frontend Dockerfile against the output directory in `angular.json`. |
| `Not Found` at `http://<host>:8283/` | Expected. The backend only serves `/admin/` and `/api/`. |
| Frontend loads but shows no data | `API_URL` was wrong when the image was built, or the origin is missing from `CORS_ORIGIN_WHITELIST`. `API_URL` requires `up -d --build`. |
| `password authentication failed for user` | Postgres applies `POSTGRES_USER` and `POSTGRES_PASSWORD` only on the very first start into an empty volume. Later changes have no effect. To apply them, run `docker compose down -v` — this deletes all data. |
| `Connection refused` for host `db` on first start | Postgres is not ready yet. `depends_on` waits for the container to start, not for the database to accept connections. `restart: unless-stopped` recovers from it; a healthcheck on `db` would avoid it entirely. |
| `docker logs` shows nothing for the backend | Python is buffering. `PYTHONUNBUFFERED=1` must be set in the backend image. |
| `permission denied` on the Docker socket (Linux) | Your user is not in the `docker` group. Use `sudo`, or add yourself to the group — see [Command conventions](#command-conventions). |