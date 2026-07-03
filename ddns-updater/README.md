# DDNS Updater

Container-friendly dynamic DNS updater with optional built-in polling.

Recommended usage is to run the container with `--interval 300` so the updater stays alive and checks every 5 minutes. If you prefer, you can still omit `--interval` and run it as a one-shot command from cron, systemd, Kubernetes CronJob, or another external scheduler.

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
python updater.py [--service cloudflare] [--dry-run] [--interval 300]
```

Options:

- `--service`: DNS provider service name (default: `cloudflare`)
- `--dry-run`: perform IP/record checks and log intended changes without updating DNS
- `--interval`: poll every `N` seconds inside the container; recommended value: `300`

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

#### Getting your Cloudflare `CF_API_TOKEN`

1. Log in to the [Cloudflare dashboard](https://dash.cloudflare.com/).
2. Go to **My Profile** (top-right avatar) > **API Tokens**.
3. Click **Create Token**.
4. Choose the **Edit zone DNS** template (or create a custom token) and scope it to:
   - Permissions: `Zone` / `DNS` / `Edit`
   - Zone Resources: `Include` / `Specific zone` / the zone you want to update
5. Click **Continue to summary**, then **Create Token**, and copy the generated token immediately (it is only shown once). Use this value for `CF_API_TOKEN`.

#### Getting your Cloudflare `CF_ZONE_ID`

1. Log in to the [Cloudflare dashboard](https://dash.cloudflare.com/).
2. Select the domain (zone) you want to update.
3. On the domain's **Overview** page, scroll down to the **API** section in the right-hand sidebar.
4. Copy the **Zone ID** value shown there. Use this value for `CF_ZONE_ID`.

## Polling and scheduling

### Recommended: built-in polling with `--interval`

The easiest way to use the updater is to let the container run its own polling loop:

```bash
docker run --rm --env-file ./ddns-updater/.env ddns-updater:latest --interval 300
```

This keeps the container running and performs a full check every 300 seconds (5 minutes):

1. validate required configuration
2. fetch the current public IP
3. look up the matching Cloudflare DNS record
4. compare record content to the detected IP
5. update only when the value changed
6. log the poll result with timestamp, IP, and whether an update occurred
7. sleep until the next interval

The updater handles `SIGINT`/`SIGTERM` so stopping the container exits the polling loop cleanly with exit code `0`.

### Recommended frequency

Recommended check interval: **every 5 minutes** (`--interval 300`).

- This gives practical responsiveness for most dynamic IP environments.
- The script only performs a write when the IP changed, so frequent checks do not imply frequent updates.

### Advanced: external scheduler / one-shot mode

If you omit `--interval`, the script runs once and exits. That is useful when you want cron, systemd, or Kubernetes to control the schedule:

```bash
docker run --rm --env-file ./ddns-updater/.env ddns-updater:latest
```

### Cron example (every 5 minutes, one-shot mode)

```cron
*/5 * * * * /usr/bin/docker run --rm --env-file /opt/ddns-updater/.env ddns-updater:latest >> /var/log/ddns-updater.log 2>&1
```

### systemd timer example (one-shot mode)

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

### Kubernetes CronJob schedule example (one-shot mode)

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

Recommended polling run:

```bash
docker run --rm --env-file ./ddns-updater/.env ddns-updater:latest --interval 300
```

One-shot run:

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

Container entrypoint is `python /app/updater.py`, which supports either one-shot mode or the internal polling loop.

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
| 0 | Success (updated, already up-to-date, or clean polling shutdown) |
| 1 | Configuration error (missing/invalid required environment variables) |
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
