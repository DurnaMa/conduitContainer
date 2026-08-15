# Conduit Container

This repository containerizes the RealWorld "Conduit" application: an Angular frontend, a Django REST backend and a PostgreSQL database, orchestrated with Docker Compose.

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
- [Continuous Deployment](#continuous-deployment)
  - [Local build](#local-build)
  - [Automated deployment](#automated-deployment)
  - [Required GitHub Secrets](#required-github-secrets)
  - [One-time VM setup](#one-time-vm-setup)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Docker installed — check with: `docker -v`
- Docker Compose installed — check with: `docker compose version`
- Host ports — default to `8282` and `8283`; change them in `.env` if they are taken.
- A `.env` file — created in the Quickstart below.

The stack runs on any Docker host: Windows or macOS with Docker Desktop, or Linux with Docker Engine.
It does not require a remote server — running it locally works as long as the host and origin variables match the address you use (see [Configuration](#configuration)).
If you run it on a remote machine, replace `localhost` with that machine's IP address everywhere below and make sure the ports are reachable through its firewall or security group.

## Command conventions

All commands are written to run as shown in **Terminal on macOS** and **bash on Linux**.

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

4. Edit `.env` and replace every placeholder. Generate `SECRET_KEY` and the two passwords with:

   ```bash
   openssl rand -base64 48    # SECRET_KEY
   openssl rand -base64 24    # POSTGRES_PASSWORD, DJANGO_SUPERUSER_PASSWORD
   ```

   `FRONTEND_IMAGE` and `BACKEND_IMAGE` stay empty — they are only set by the deployment workflow on the VM.

> [!IMPORTANT]
> Every placeholder in `.env.example` is written in angle brackets, for example `HOST=<VM-IP>`. Compose treats those as ordinary characters and starts the stack without a single warning, so an unreplaced placeholder surfaces much later as a `400 Bad Request` or a rejected database password. Verify with `grep -n '<' .env` — no output means the file is clean.

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
| `docker-compose.yaml` | Defines the `frontend`, `backend` and `db` services, their ports, the `db` volume, the health check and all environment variables |
| `.env.example` | Template listing every variable the compose file references, without secret values |
| `.gitignore` | Keeps secrets (`.env`), build output and caches out of Git |
| `.github/workflows/deployment.yaml` | Builds both images on a GitHub runner, pushes them to GHCR and deploys them to the VM over SSH |
| `conduit-frontend/Dockerfile` | Multi-stage build: Angular build with Node, served by Nginx |
| `conduit-frontend/nginx.conf` | Nginx server block with `try_files`, so deep links and page reloads are answered with `index.html` instead of a 404 |
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

The database deliberately has no host port. Only the backend reaches it, over the internal Docker network under the hostname `db`. All services use `restart: unless-stopped`.

`db` has a `pg_isready` health check, and `backend` waits for `condition: service_healthy`. Without it the backend starts before Postgres accepts connections, crashes in `migrate` and is only recovered by the restart policy a few seconds later.

> [!NOTE]
> Since PostgreSQL 18, `PGDATA` lives in `/var/lib/postgresql` instead of `/var/lib/postgresql/data`. The `db` volume is mounted accordingly.
> Using the older path with an 18.x image would silently leave the data unpersisted.

## Access

Ports shown are the defaults from `.env.example`. If you changed `PORTS_FRONTEND`
or `PORTS_BACKEND`, use those instead.

Replace `localhost` with the host's IP address if you are not running the stack on your own machine.

| What | URL |
|---|---|
| Frontend | `http://<host>:8282` |
| API | `http://<host>:8283/api/` |
| Django admin | `http://<host>:8283/admin/` |

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
| `FRONTEND_IMAGE` | Image to run instead of building from source. Leave empty for local development | *(blank)* |
| `BACKEND_IMAGE` | Same for the backend | *(blank)* |
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
> `API_URL` needs a scheme (`http://host:port/api`) because the browser calls that URL. `ALLOWED_HOSTS` and `CORS_ORIGIN_WHITELIST` must not have one — Django compares host names, and the CORS middleware compares the `netloc` of the `Origin` header, which is `host:port` with the scheme already stripped. An entry written as `http://host:8282` never matches, and the response silently arrives without an `Access-Control-Allow-Origin` header.

> [!IMPORTANT]
> A variable that is set but empty is not the same as a missing one. `os.environ.get('X', 'default')` returns an empty string for `X=`, not the default. An empty `SECRET_KEY` makes Django fail when it signs a session.

### Build time vs. runtime

Which variables take effect when decides whether a change needs a rebuild:

| Build time — needs `--build` | Runtime — recreating the container is enough |
|---|---|
| `API_URL` (compiled into the Angular bundle), `nginx.conf` (copied into the frontend image) | `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS`, `CORS_ORIGIN_WHITELIST`, `POSTGRES_*`, `DJANGO_SUPERUSER_PASSWORD` |

```bash
# after changing HOST, a port, or nginx.conf
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

> [!NOTE]
> The health check covers the database, not the migrations. Running `createsuperuser` immediately after `up -d` can still print `Not checking migrations …` while `migrate` is still working. Wait a few seconds and confirm with `docker compose exec backend python manage.py showmigrations` — no line may show `[ ]`.

### Verify

1. Resolve the compose file against `.env` and check it is valid:

   > [!WARNING]
   > This prints all variables in plain text, passwords included. Do not run it in a shared screen recording.

   ```bash
   docker compose config
   ```

2. Check that all three containers are running and `db` is healthy:

   ```bash
   docker compose ps
   ```

3. Check what the backend actually received — more reliable than reading `.env`, which differs per machine:

   ```bash
   docker compose exec backend printenv | grep -E 'ALLOWED_HOSTS|CORS'
   ```

4. Call the API and check the CORS header:

   ```bash
   IP=$(grep '^HOST=' .env | cut -d= -f2)
   curl -i -H "Host: $IP" -H "Origin: http://$IP:8282" \
        http://localhost:8283/api/tags | grep -iE 'HTTP/|server|access-control'
   ```

   Expect status `200`, a `Server: gunicorn` header and `Access-Control-Allow-Origin: http://<host>:8282`. The first confirms a WSGI server is serving the app rather than a development server, the second that the browser will accept the response.

   > [!NOTE]
   > On a cloud VM, calling its own public IP can time out even though everything works — the public address is mapped in front of the instance rather than bound to its interface, so the packet never comes back. That is why the command above connects to `localhost` and sets `Host` and `Origin` by hand: `Host` is what Django checks against `ALLOWED_HOSTS`, `Origin` is what the CORS middleware checks. From your own machine the public address works normally.

5. Check that deep links are served by the SPA, not by Nginx's file lookup:

   ```bash
   curl -o /dev/null -w "%{http_code}\n" http://localhost:8282/login
   ```

   Expect `200`. A `404` means `nginx.conf` did not make it into the image.

6. Open the frontend and navigate through it. In the browser's network tab, the requests must go to `http://<host>:8283/api/...`, not to `api.realworld.io`.

7. Confirm data persistence: create something in the admin, then run `docker compose down` followed by `docker compose up -d`. The record must still be there.

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

## Continuous Deployment

This repository supports two independent ways to run the stack. You choose one by how you fill in `.env` — the `docker-compose.yaml` is the same for both, because every service declares both an `image:` and a `build:`. When the image variable is empty, Compose builds from source; when it is set, Compose pulls the finished image and ignores `build:`.

| | Local build | Automated deployment (CI/CD) |
|---|---|---|
| For | Running or developing the app on any Docker host | Shipping to a remote VM automatically on every push to `main` |
| Images | Built on your machine from source | Built on a GitHub runner, pushed to GHCR, pulled by the VM |
| You configure | `.env` only | `.env` on the VM **and** GitHub Secrets in your repo |
| `API_URL` (frontend → backend) | baked in at build time from `.env` | baked in at build time from the `HOST` **secret** |
| Command | `docker compose up -d --build` | `git push` to `main` (or a manual run) |

> [!NOTE]
> Cloning this repository does **not** copy any GitHub Secrets — they belong to the original repo. To only run the app locally you need none of them; `.env` is enough. You only need the secrets below if you set up the automated deployment in **your own** fork.

### Local build

Follow the [Quickstart](#quickstart). Leave `FRONTEND_IMAGE` and `BACKEND_IMAGE` empty in `.env`; Compose then falls back to the `:local` defaults and builds from source. No GitHub Secrets and no VM are required.

### Automated deployment

Pushing to `main`, pushing a `v*.*.*` tag, or a manual run (`workflow_dispatch`) triggers `.github/workflows/deployment.yaml`, which runs three jobs in sequence:

1. **`build`** — builds the `frontend` and `backend` images (one matrix job each) and pushes them to the GitHub Container Registry as `ghcr.io/<owner>/conduit-frontend` and `ghcr.io/<owner>/conduit-backend`. Each image is tagged with the short commit SHA (`sha-<short>`), plus `latest` on `main` and the version on a `v*.*.*` tag. The build runs entirely on the GitHub runner — **not** on the VM.
2. **`test`** — pulls the freshly built images, starts the full stack with a throwaway `.env`, waits for `db` to become healthy and checks that the backend answers `200`. A failure here stops the pipeline before anything reaches the VM.
3. **`deploy`** — copies the current `docker-compose.yaml` to the VM over SSH, then runs `docker compose pull` and `docker compose up -d --remove-orphans` (detached mode). It runs only on `main` or a manual dispatch, never on a pull request. Any failing step aborts the workflow with an error.

#### Required GitHub Secrets

Set these under **Settings → Secrets and variables → Actions** in your repository. None are stored in the code, and none are needed for a local build.

| Secret | Purpose |
|---|---|
| `SSH_HOST` | IP address or hostname of the deployment VM |
| `SSH_USER` | SSH user on the VM |
| `SSH_PRIVATE_KEY` | Private key whose public half is in `~/.ssh/authorized_keys` on the VM |
| `HOST` | IP or hostname of the VM. Used at **build time** to compile `API_URL` into the frontend image, so the browser talks to the right backend |

`PORTS_BACKEND` is optional — set it only if the backend runs on a non-default host port; it defaults to `8283`.

> [!IMPORTANT]
> `HOST` appears in two unrelated places and both must match:
> - as a **GitHub Secret** — baked into the frontend image at build time (`API_URL`);
> - in the VM's **`.env`** — read at runtime for `ALLOWED_HOSTS` and the CORS origin.
>
> If they disagree, the stack starts but the frontend loads no data.

`GITHUB_TOKEN` is provided automatically by GitHub Actions and needs no setup — it authenticates the push to GHCR. Its `packages: write` permission is declared in the workflow.

#### One-time VM setup

The workflow only ever copies `docker-compose.yaml`; everything else must exist on the VM beforehand:

1. Docker and the Compose plugin are installed, and the SSH user is in the `docker` group.
2. The deploy directory exists and matches `DEPLOY_PATH` in `deployment.yaml` (default `/opt/conduit`):
   ```bash
   sudo mkdir -p /opt/conduit
   sudo chown $USER:$USER /opt/conduit
   ```
3. A real `.env` is placed at `/opt/conduit/.env` — done manually, once, never touched by the workflow, so secrets never pass through CI logs. Verify with `grep -n '<' /opt/conduit/.env` (no output means it is clean).
4. The public half of `SSH_PRIVATE_KEY` is in `~/.ssh/authorized_keys`. Test from your own machine, not from the VM (a VM connecting to itself proves nothing about GitHub's access):
   ```bash
   ssh -i ~/.ssh/<your_key> <SSH_USER>@<VM-IP> "echo ok"
   ```

From then on, every push to `main` rebuilds the images and restarts the stack on the VM automatically.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Bad Request (400)` on every URL, including `/admin/` | The host you are using is not in `ALLOWED_HOSTS`. Django checks this before routing, so every path is affected. It compares the host name without the port. |
| `Bad Request (400)` right after setup, or a database password that is rejected | Placeholders from `.env.example` are still in `.env`. Compose accepts `<VM-IP>` as a literal value without warning. Check with `grep -n '<' .env`, then with `docker compose exec backend printenv`. |
| Request to the API times out instead of failing fast | Either the port is closed in the firewall or security group, or you are calling the VM's public IP from the VM itself (see the note under [Verify](#verify)). `Connection refused` would mean the opposite: no listener, so the container is down. |
| `Welcome to nginx!` instead of the app | `index.html` is not directly in `/usr/share/nginx/html`. Check the `COPY` path in the frontend Dockerfile against the output directory in `angular.json`. |
| `404` when reloading a subpage, while clicking through the app works | `nginx.conf` is not in the image. Angular routes client-side; on a reload Nginx looks for a real file called `/login`. Check the `COPY nginx.conf` line in the frontend Dockerfile. |
| `Not Found` at `http://<host>:8283/` | Expected. The backend only serves `/admin/` and `/api/`. |
| Frontend loads but shows no data | `API_URL` was wrong when the image was built, or the origin does not match `CORS_ORIGIN_WHITELIST` — remember that entry takes no scheme. `API_URL` requires `up -d --build`. |
| `password authentication failed for user` | Postgres applies `POSTGRES_USER` and `POSTGRES_PASSWORD` only on the very first start into an empty volume. Later changes have no effect. To apply them, run `docker compose down -v` — this deletes all data. |
| `Connection refused` for host `db` on first start | Postgres is not ready yet. The `pg_isready` health check on `db` plus `condition: service_healthy` on `backend` prevents this; without them `depends_on` only waits for the container to start. |
| An `adminer` container keeps reappearing | Left over from an earlier version of the compose file. Remove it with `docker compose down --remove-orphans`. |
| `docker logs` shows nothing for the backend | Python is buffering. `PYTHONUNBUFFERED=1` must be set in the backend image. |
| `permission denied` on the Docker socket (Linux) | Your user is not in the `docker` group. Use `sudo`, or add yourself to the group — see [Command conventions](#command-conventions). |