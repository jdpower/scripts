# DDNS Updater

A small, low-maintenance dynamic DNS updater designed to run inside a container on a schedule.

## Folder structure

This project lives in the following folder inside this repository:

```text
ddns-updater/
├── README.md
├── Dockerfile
├── updater.py
├── test_updater.py
└── .env.example
```

## Provider support

The updater accepts a **DNS provider/service name** so the interface can be extended later.

### Default provider

- `cloudflare` is the **default** provider.

### Planned usage

```bash
python updater.py --service cloudflare --dry-run
```

If no provider is supplied, the script behaves as if this was provided:

```bash
python updater.py --service cloudflare
```

This keeps Cloudflare as the default while leaving room to support other providers later.

## Does this use cron?

**The updater script itself does not contain a cron job.** It is a **one-shot program**: each time it runs, it performs a single check-and-update cycle and then exits.

A scheduler is what calls the container repeatedly. You can use:

- **Host cron** on a Linux machine running Docker
- **A systemd timer** on Linux
- **Kubernetes CronJob** if you run this in Kubernetes
- **A platform scheduler** such as a cloud scheduled task service

This is the recommended model because it keeps the container simple and more secure:

- no cron daemon running inside the container
- no long-lived process to supervise
- easier logging and failure handling
- simpler image and smaller attack surface

## How often should it check?

A practical default is **every 5 minutes**.

That is frequent enough for most home or small-office dynamic IP use cases, while avoiding unnecessary API traffic.

Recommended guidance:

- **Every 5 minutes**: best default for most users
- **Every 10–15 minutes**: good if your IP changes rarely and you want fewer checks
- **Every 1 minute**: usually unnecessary unless you have an unusually sensitive failover requirement

The script first compares the current public IP with the existing DNS record and only calls the provider API when the value actually changed.

That means a 5-minute schedule does **not** imply a write every 5 minutes — only a read/check every 5 minutes, with writes only on change.

## How it works

1. Load and validate configuration from environment variables (typically supplied via `.env`).
2. Determine the provider from `--service` or default to `cloudflare`.
3. Fetch the current public IP over HTTPS.
4. Look up the target DNS record in the provider API (for Cloudflare, by `CF_RECORD_ID` if provided, otherwise by exact name + type match).
5. Compare the current record value to the detected IP.
6. If different, update **only that record**. If unchanged, exit without writing.
7. Log a minimal, secret-free result and exit with a specific status code.

No third-party dependencies are required for the planned Python implementation.

## Requirements

- Container runtime (Docker, containerd, or a Kubernetes cluster), **or** Python 3.9+ if run outside a container.
- Outbound HTTPS (443) access from the container to:
  - the selected provider API
  - the configured public IP discovery endpoint
- DNS resolution available inside the container.
- CA certificates installed in the image (missing on some minimal base images).
- For Cloudflare, an API token scoped to the minimum needed:
  - `Zone:Read`
  - `DNS:Edit`
  - restricted to the specific zone

## Configuration

All configuration is supplied via environment variables, normally loaded from a `.env` file that is **never committed to git or baked into the image**.

### General

| Variable | Required | Description |
|---|---|---|
| `DDNS_SERVICE` | No | Provider/service name. Default: `cloudflare` |

### Cloudflare

| Variable | Required | Description |
|---|---|---|
| `CF_API_TOKEN` | Yes for Cloudflare | Cloudflare API token (least-privilege, zone-scoped) |
| `CF_ZONE_ID` | Yes for Cloudflare | Cloudflare zone ID for the domain |
| `CF_RECORD_NAME` | Yes for Cloudflare | Fully-qualified DNS name to update, e.g. `home.example.com` |
| `CF_RECORD_TYPE` | Yes for Cloudflare | `A` (IPv4) or `AAAA` (IPv6) |
| `CF_RECORD_ID` | No | Exact Cloudflare record ID. If set, skips name/type lookup entirely — recommended for tighter scoping |

### `.env` file

```env
DDNS_SERVICE=cloudflare
CF_API_TOKEN=your-scoped-token
CF_ZONE_ID=your-zone-id
CF_RECORD_NAME=home.example.com
CF_RECORD_TYPE=A
CF_RECORD_ID=
```

- Set file permissions to `600`.
- Add `.env` to both `.gitignore` and `.dockerignore`.
- Never pass the token as a command-line argument.

## Usage

Build:

```bash
docker build -t ddns-updater ./ddns-updater
```

Dry run using the default provider (`cloudflare`):

```bash
docker run --rm --env-file .env ddns-updater --dry-run
```

Dry run with an explicit provider:

```bash
docker run --rm --env-file .env ddns-updater --service cloudflare --dry-run
```

Live run:

```bash
docker run --rm --env-file .env ddns-updater
```

### Planned help output behavior

The script help should document:

- `--service` to select the DNS provider
- default provider is `cloudflare`
- `--dry-run` to perform all checks without modifying DNS

Example intent:

```bash
python updater.py --help
```

## Scheduling the container

### Option 1: Host cron with Docker

Example cron entry to run every 5 minutes:

```cron
*/5 * * * * docker run --rm --env-file /opt/ddns-updater/.env ddns-updater >> /var/log/ddns-updater.log 2>&1
```

This:
- starts the container every 5 minutes
- injects environment variables from `/opt/ddns-updater/.env`
- removes the container after completion with `--rm`
- appends stdout/stderr to a log file

Use absolute paths in cron, protect the `.env` file, and rotate logs if needed.

### Option 2: systemd timer

Example service unit:

```ini
[Unit]
Description=DDNS updater

[Service]
Type=oneshot
ExecStart=/usr/bin/docker run --rm --env-file /opt/ddns-updater/.env ddns-updater
```

Example timer unit:

```ini
[Unit]
Description=Run DDNS updater every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=ddns-updater.service

[Install]
WantedBy=timers.target
```

### Option 3: Kubernetes CronJob

Example schedule for every 5 minutes:

```yaml
schedule: "*/5 * * * *"
```

In Kubernetes, secrets should generally be provided via a Secret rather than a mounted `.env` file.

## Why not run cron inside the container?

You *can*, but it is usually not the best choice.

Running cron inside the image means:

- a long-lived container instead of a one-shot task
- more image complexity
- more process supervision concerns
- harder signal handling and logging
- more moving parts to maintain

The preferred approach is to keep the image focused on the updater only and let an external scheduler run it.

## Verifying provider connectivity before scheduling

For Cloudflare specifically:

1. **Check egress from the container:**
   ```bash
   docker run --rm curlimages/curl -s -o /dev/null -w '%{http_code}\n' https://api.cloudflare.com
   ```
2. **Verify the token without touching DNS:**
   ```bash
   curl -s -H "Authorization: Bearer $CF_API_TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify
   ```
3. **Run the script in `--dry-run` mode.**

## Dockerfile and image details

Recommended base image:

- **`python:3.12-alpine`**

Why:

- includes Python already
- smaller than many full Linux images
- suitable for a standard-library-only script
- easy to understand operationally

Important image details:

- install `ca-certificates`
- run as a **non-root user**
- do **not** copy `.env` into the image
- keep the image single-purpose: run one updater invocation and exit

Example Dockerfile shape:

```dockerfile
FROM python:3.12-alpine

RUN apk add --no-cache ca-certificates \
    && adduser -D -h /app appuser

WORKDIR /app
COPY updater.py /app/updater.py
COPY test_updater.py /app/test_updater.py
COPY README.md /app/README.md

USER appuser
ENTRYPOINT ["python", "/app/updater.py"]
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success — updated or no change needed |
| 1 | Configuration error |
| 2 | Network or public IP discovery failure |
| 3 | Provider authentication error |
| 4 | Record lookup error |
| 5 | Provider update failure |
| 6 | Unsupported service/provider |

## Testing

Run the test suite:

```bash
python -m unittest discover
```

## Security notes

- Least-privilege provider credentials
- For Cloudflare, use a zone-scoped API token — never a global API key
- Secrets are read only from environment or `.env` at runtime, never logged, never baked into the image
- Container runs as a non-root user
- HTTPS-only outbound calls, with timeouts on every request
- Update-only by default
- Exact record targeting via `CF_RECORD_ID` recommended
