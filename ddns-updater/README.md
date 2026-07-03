# DDNS Updater

Container-friendly dynamic DNS updater with built-in polling support.

The script supports two modes:

- **Polling mode** (recommended): pass `--interval-seconds N` or set `DDNS_INTERVAL_SECONDS=N`. The script loops internally, checking and updating every N seconds. Stop the container with `docker stop` for a clean exit.
- **One-shot mode** (default): no interval specified. The script runs once and exits. Use an external scheduler (cron, systemd timer, Kubernetes CronJob) to call it repeatedly.

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
python updater.py [--service cloudflare] [--dry-run] [--interval-seconds N]
```

Options:

- `--service`: DNS provider service name (default: `cloudflare`)
- `--dry-run`: perform IP/record checks and log intended changes without updating DNS
- `--interval-seconds N`: run in polling loop, checking every N seconds; if omitted, run once (one-shot mode)

Unsupported providers fail with exit code `6`.

## Configuration

Configuration is read from environment variables. `.env` is also supported at runtime (default path: `./.env`; override with `DDNS_ENV_FILE`).

### General

| Variable | Required | Description |
|---|---|---|
| `DDNS_SERVICE` | No | Default service when `--service` is not provided (`cloudflare`) |
| `DDNS_INTERVAL_SECONDS` | No | Polling interval in seconds; enables polling mode if set. Overridden by `--interval-seconds` if both are present. |
| `DDNS_ENV_FILE` | No | Optional path to env file (default `.env`) |

### Cloudflare

| Variable | Required | Description |
|---|---|---|
| `API_TOKEN` | Yes | Cloudflare API token |
| `ZONE_ID` | Yes | Cloudflare zone ID |
| `RECORD_NAME` | Yes | DNS name to update (for example `home.example.com`) |
| `RECORD_TYPE` | Yes | `A` or `AAAA` |
| `RECORD_ID` | No | If set, updater targets this exact DNS record ID directly |

`RECORD_ID` avoids name/type lookup ambiguity and updates one known record.

All four required Cloudflare variables (`API_TOKEN`, `ZONE_ID`, `RECORD_NAME`, `RECORD_TYPE`) are validated at startup before any network call. The script exits immediately with code 1 and logs which variables are missing if any are absent.

#### Getting your Cloudflare `API_TOKEN`

1. Log in to the [Cloudflare dashboard](https://dash.cloudflare.com/).
2. Go to **My Profile** (top-right avatar) > **API Tokens**.
3. Click **Create Token**.
4. Choose the **Edit zone DNS** template (or create a custom token) and scope it to:
   - Permissions: `Zone` / `DNS` / `Edit`
   - Zone Resources: `Include` / `Specific zone` / the zone you want to update
5. Click **Continue to summary**, then **Create Token**, and copy the generated token immediately (it is only shown once). Use this value for `API_TOKEN`.

#### Getting your Cloudflare `ZONE_ID`

1. Log in to the [Cloudflare dashboard](https://dash.cloudflare.com/).
2. Select the domain (zone) you want to update.
3. On the domain's **Overview** page, scroll down to the **API** section in the right-hand sidebar.
4. Copy the **Zone ID** value shown there. Use this value for `ZONE_ID`.

## Polling with built-in scheduler

When `--interval-seconds` or `DDNS_INTERVAL_SECONDS` is provided, the script runs a polling loop internally:

1. Validate configuration (fail fast if any required variable is missing)
2. Loop indefinitely:
   - Fetch current public IP
   - Look up DNS record
   - Update if the IP has changed; skip if unchanged
   - Log timestamp, detected IP, current record value, and whether an update was made
   - Sleep for the specified interval (in seconds)
3. Exit cleanly with code 0 on SIGTERM or SIGINT (Ctrl-C / `docker stop`)

**Interval unit:** seconds. Recommended: `300` seconds (5 minutes).

### Examples

```bash
# Using CLI flag
python updater.py --interval-seconds 300

# Using environment variable
DDNS_INTERVAL_SECONDS=300 python updater.py

# In Docker with built-in polling (CLI flag)
docker run --rm --env-file .env ddns-updater --interval-seconds 300

# In Docker with built-in polling (env var — add DDNS_INTERVAL_SECONDS=300 to .env)
docker run --rm --env-file .env ddns-updater

# CLI flag overrides env var if both are present
docker run --rm --env-file .env ddns-updater --interval-seconds 600
```

### One-shot mode (no polling)

```bash
# One-shot mode — run once and exit
python updater.py

# In Docker, one-shot mode
docker run --rm --env-file .env ddns-updater
```

## Scheduling model and frequency

### Easy option (recommended): built-in polling

Pass `--interval-seconds` or set `DDNS_INTERVAL_SECONDS` in `.env`. The container runs continuously and polls automatically. No external scheduler is required.

```bash
docker run -d --restart unless-stopped --env-file /opt/ddns-updater/.env ddns-updater:latest --interval-seconds 300
```

### Advanced option: external scheduler (one-shot mode)

For environments where you already use a scheduler, keep the container in one-shot mode and let the scheduler call it.

#### Cron example (every 5 minutes)

```cron
*/5 * * * * /usr/bin/docker run --rm --env-file /opt/ddns-updater/.env ddns-updater:latest >> /var/log/ddns-updater.log 2>&1
```

#### systemd timer example

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

#### Kubernetes CronJob schedule example

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

Live run (one-shot):

```bash
docker run --rm --env-file ./ddns-updater/.env ddns-updater:latest
```

Live run (polling every 5 minutes):

```bash
docker run -d --restart unless-stopped --env-file ./ddns-updater/.env ddns-updater:latest --interval-seconds 300
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
| 0 | Success (updated, already up-to-date, or clean shutdown from polling) |
| 1 | Configuration error (missing required env vars or invalid value) |
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

