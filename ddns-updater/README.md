# DDNS Updater

Container-friendly one-shot dynamic DNS updater.

This script is designed to run once and exit. Use an external scheduler (cron, systemd timer, Kubernetes CronJob, or cloud scheduler) to invoke it repeatedly.

## Folder structure

```text
ddns-updater/
├── README.md
├── Dockerfile
├── updater.py
├── test_updater.py
└── .env.example
```

## CLI usage

```bash
python updater.py [--service cloudflare] [--dry-run]
```

Options:

- `--service`: DNS provider service name (default: `cloudflare`)
- `--dry-run`: perform IP/record checks and log intended changes without updating DNS

Unsupported providers fail with exit code `6`.

## Configuration

Configuration is read from environment variables. `.env` is also supported at runtime (default path: `./.env`; override with `DDNS_ENV_FILE`).

### General

| Variable | Required | Description |
|---|---|---|
| `DDNS_SERVICE` | No | Default service when `--service` is not provided (`cloudflare`) |
| `DDNS_ENV_FILE` | No | Optional path to env file (default `.env`) |

### Cloudflare

| Variable | Required | Description |
|---|---|---|
| `CF_API_TOKEN` | Yes | Cloudflare API token |
| `CF_ZONE_ID` | Yes | Cloudflare zone ID |
| `CF_RECORD_NAME` | Yes | DNS name to update (for example `home.example.com`) |
| `CF_RECORD_TYPE` | Yes | `A` or `AAAA` |
| `CF_RECORD_ID` | No | If set, updater targets this exact DNS record ID directly |

`CF_RECORD_ID` avoids name/type lookup ambiguity and updates one known record.

## Scheduling model and frequency

The updater itself does **not** run cron internally.

Recommended check interval: **every 5 minutes**.

- This gives practical responsiveness for most dynamic IP environments.
- The script only performs a write when the IP changed, so frequent checks do not imply frequent updates.

### Cron example (every 5 minutes)

```cron
*/5 * * * * /usr/bin/docker run --rm --env-file /opt/ddns-updater/.env ddns-updater:latest >> /var/log/ddns-updater.log 2>&1
```

### systemd timer example

`/etc/systemd/system/ddns-updater.service`

```ini
[Unit]
Description=DDNS updater one-shot

[Service]
Type=oneshot
ExecStart=/usr/bin/docker run --rm --env-file /opt/ddns-updater/.env ddns-updater:latest
```

`/etc/systemd/system/ddns-updater.timer`

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

### Kubernetes CronJob schedule example

```yaml
schedule: "*/5 * * * *"
```

## Docker build and run

Build from repo root:

```bash
docker build -t ddns-updater:latest ./ddns-updater
```

Dry run:

```bash
docker run --rm --env-file ./ddns-updater/.env ddns-updater:latest --dry-run
```

Live run:

```bash
docker run --rm --env-file ./ddns-updater/.env ddns-updater:latest
```

Explicit service:

```bash
docker run --rm --env-file ./ddns-updater/.env ddns-updater:latest --service cloudflare
```

## Dockerfile/image rationale

The Dockerfile uses `python:3.12-slim` because:

- the updater is Python standard-library-only (no extra runtime dependencies)
- `slim` keeps image size and attack surface low while remaining straightforward to maintain
- CA certificates are explicitly installed for HTTPS API verification
- process runs as a dedicated non-root user
- only `updater.py` is copied, so `.env` is not baked into the image

Container entrypoint is one-shot: `python /app/updater.py`.

## Cloudflare connectivity verification

Before scheduling, verify network and auth:

1. API reachability from container network:

```bash
docker run --rm curlimages/curl -s -o /dev/null -w '%{http_code}\n' https://api.cloudflare.com
```

2. Token verification (does not modify DNS): call `https://api.cloudflare.com/client/v4/user/tokens/verify` with your Cloudflare bearer token in the `Authorization` header.

3. Run updater in dry-run mode.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (updated or already up-to-date) |
| 1 | Configuration error |
| 2 | Network/public IP lookup error |
| 3 | Cloudflare authentication/authorization error |
| 4 | DNS record lookup error |
| 5 | DNS update error |
| 6 | Unsupported provider |

## Security notes

- Secrets are read from environment/`.env`; no secret CLI flags are used.
- API token values are never logged by the updater.
- HTTPS is enforced for all outbound requests with explicit timeouts.
- Use least-privilege Cloudflare token scopes (`Zone:Read`, `DNS:Edit`) for only the required zone.

## Tests

Run tests without real network/API access:

```bash
python -m unittest discover -s ddns-updater -p 'test_*.py'
```
