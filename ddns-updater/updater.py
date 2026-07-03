#!/usr/bin/env python3
"""One-shot DDNS updater with Cloudflare support."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import sys
from dataclasses import dataclass
from typing import Dict, Optional
from urllib import error, parse, request

EXIT_SUCCESS = 0
EXIT_CONFIG = 1
EXIT_NETWORK = 2
EXIT_AUTH = 3
EXIT_LOOKUP = 4
EXIT_UPDATE = 5
EXIT_UNSUPPORTED_PROVIDER = 6

DEFAULT_SERVICE = "cloudflare"
DEFAULT_TIMEOUT_SECONDS = 10
CLOUDFLARE_API_BASE = "https://api.cloudflare.com/client/v4"
IP_DISCOVERY_ENDPOINTS = {
    "A": "https://api.ipify.org?format=json",
    "AAAA": "https://api64.ipify.org?format=json",
}


class UpdaterError(Exception):
    """Updater error with an explicit exit code."""

    def __init__(self, exit_code: int, message: str) -> None:
        super().__init__(message)
        self.exit_code = exit_code


@dataclass
class CloudflareConfig:
    api_token: str
    zone_id: str
    record_name: str
    record_type: str
    record_id: str = ""


def log_info(message: str) -> None:
    print(message)


def log_error(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)


def load_dotenv(path: str) -> Dict[str, str]:
    if not path or not os.path.exists(path):
        return {}

    values: Dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as env_file:
        for raw_line in env_file:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue

            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()

            if not key:
                continue

            if (value.startswith('"') and value.endswith('"')) or (
                value.startswith("'") and value.endswith("'")
            ):
                value = value[1:-1]

            values[key] = value

    return values


def request_json(
    url: str,
    *,
    method: str = "GET",
    headers: Optional[Dict[str, str]] = None,
    payload: Optional[Dict[str, object]] = None,
    timeout: int = DEFAULT_TIMEOUT_SECONDS,
) -> tuple[int, Dict[str, object]]:
    if not url.startswith("https://"):
        raise UpdaterError(EXIT_NETWORK, "refusing non-HTTPS request")

    body = None
    request_headers = {"Accept": "application/json", **(headers or {})}
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        request_headers.setdefault("Content-Type", "application/json")

    req = request.Request(url=url, data=body, headers=request_headers, method=method)

    raw_response = ""
    status_code: int
    try:
        with request.urlopen(req, timeout=timeout) as response:
            raw_response = response.read().decode("utf-8", errors="replace")
            status_code = response.getcode()
    except error.HTTPError as exc:
        raw_response = exc.read().decode("utf-8", errors="replace")
        status_code = exc.code
    except error.URLError as exc:
        reason = exc.reason if hasattr(exc, "reason") else "network error"
        raise UpdaterError(EXIT_NETWORK, f"network request failed: {reason}") from exc

    if not raw_response.strip():
        return status_code, {}

    try:
        parsed = json.loads(raw_response)
        if isinstance(parsed, dict):
            return status_code, parsed
        return status_code, {"result": parsed}
    except json.JSONDecodeError:
        return status_code, {"raw": raw_response}


def cloudflare_headers(api_token: str) -> Dict[str, str]:
    return {
        "Authorization": "Bearer " + api_token,
        "Content-Type": "application/json",
        "User-Agent": "ddns-updater/1.0",
    }


def is_auth_failure(status_code: int, body: Dict[str, object]) -> bool:
    if status_code in (401, 403):
        return True

    errors = body.get("errors") if isinstance(body, dict) else None
    if not isinstance(errors, list):
        return False

    for item in errors:
        if not isinstance(item, dict):
            continue
        code = item.get("code")
        if code in {9103, 9106, 9107, 9109, 10000}:
            return True
        message = str(item.get("message", "")).lower()
        if "auth" in message or "token" in message or "permission" in message:
            return True

    return False


def cloudflare_error_summary(body: Dict[str, object], fallback: str) -> str:
    errors = body.get("errors") if isinstance(body, dict) else None
    if isinstance(errors, list) and errors:
        first = errors[0]
        if isinstance(first, dict):
            message = str(first.get("message", "")).strip()
            if message:
                return message
    return fallback


def load_cloudflare_config(env: Dict[str, str]) -> CloudflareConfig:
    required = {
        "API_TOKEN": env.get("API_TOKEN", "").strip(),
        "ZONE_ID": env.get("ZONE_ID", "").strip(),
        "RECORD_NAME": env.get("RECORD_NAME", "").strip(),
        "RECORD_TYPE": env.get("RECORD_TYPE", "").strip().upper(),
    }

    missing = [key for key, value in required.items() if not value]
    if missing:
        raise UpdaterError(EXIT_CONFIG, f"missing required configuration: {', '.join(missing)}")

    if required["RECORD_TYPE"] not in {"A", "AAAA"}:
        raise UpdaterError(EXIT_CONFIG, "RECORD_TYPE must be A or AAAA")

    return CloudflareConfig(
        api_token=required["API_TOKEN"],
        zone_id=required["ZONE_ID"],
        record_name=required["RECORD_NAME"],
        record_type=required["RECORD_TYPE"],
        record_id=env.get("RECORD_ID", "").strip(),
    )


def fetch_public_ip(record_type: str) -> str:
    endpoint = IP_DISCOVERY_ENDPOINTS[record_type]
    status_code, body = request_json(endpoint, timeout=8)

    if status_code != 200:
        raise UpdaterError(EXIT_NETWORK, f"public IP lookup failed (HTTP {status_code})")

    ip_value = str(body.get("ip", "")).strip()
    if not ip_value:
        raise UpdaterError(EXIT_NETWORK, "public IP lookup returned no IP value")

    try:
        ip_obj = ipaddress.ip_address(ip_value)
    except ValueError as exc:
        raise UpdaterError(EXIT_NETWORK, "public IP lookup returned an invalid IP") from exc

    if record_type == "A" and ip_obj.version != 4:
        raise UpdaterError(EXIT_NETWORK, "public IP lookup did not return an IPv4 address")
    if record_type == "AAAA" and ip_obj.version != 6:
        raise UpdaterError(EXIT_NETWORK, "public IP lookup did not return an IPv6 address")

    return ip_value


def cloudflare_lookup_record(config: CloudflareConfig) -> Dict[str, object]:
    headers = cloudflare_headers(config.api_token)

    if config.record_id:
        status_code, body = request_json(
            f"{CLOUDFLARE_API_BASE}/zones/{config.zone_id}/dns_records/{config.record_id}",
            headers=headers,
        )
        if is_auth_failure(status_code, body):
            raise UpdaterError(EXIT_AUTH, "Cloudflare authentication failed")
        if status_code >= 400 or not body.get("success", False):
            summary = cloudflare_error_summary(body, "Cloudflare record lookup failed")
            raise UpdaterError(EXIT_LOOKUP, f"Cloudflare record lookup failed: {summary}")

        result = body.get("result")
        if not isinstance(result, dict):
            raise UpdaterError(EXIT_LOOKUP, "Cloudflare record lookup returned an invalid response")

        return result

    query = parse.urlencode(
        {
            "name": config.record_name,
            "type": config.record_type,
            "per_page": 2,
            "page": 1,
        }
    )
    status_code, body = request_json(
        f"{CLOUDFLARE_API_BASE}/zones/{config.zone_id}/dns_records?{query}", headers=headers
    )

    if is_auth_failure(status_code, body):
        raise UpdaterError(EXIT_AUTH, "Cloudflare authentication failed")
    if status_code >= 400 or not body.get("success", False):
        summary = cloudflare_error_summary(body, "Cloudflare record lookup failed")
        raise UpdaterError(EXIT_LOOKUP, f"Cloudflare record lookup failed: {summary}")

    result = body.get("result")
    if not isinstance(result, list):
        raise UpdaterError(EXIT_LOOKUP, "Cloudflare record lookup returned an invalid result")

    if len(result) != 1:
        raise UpdaterError(
            EXIT_LOOKUP,
            f"expected exactly one DNS record match for {config.record_name} ({config.record_type}), found {len(result)}",
        )

    return result[0]


def cloudflare_update_record(config: CloudflareConfig, record: Dict[str, object], new_ip: str) -> None:
    record_id = str(record.get("id", "")).strip()
    if not record_id:
        raise UpdaterError(EXIT_LOOKUP, "Cloudflare response missing record id")

    payload: Dict[str, object] = {
        "type": str(record.get("type") or config.record_type),
        "name": str(record.get("name") or config.record_name),
        "content": new_ip,
    }

    ttl = record.get("ttl")
    proxied = record.get("proxied")
    if isinstance(ttl, int):
        payload["ttl"] = ttl
    if isinstance(proxied, bool):
        payload["proxied"] = proxied

    status_code, body = request_json(
        f"{CLOUDFLARE_API_BASE}/zones/{config.zone_id}/dns_records/{record_id}",
        method="PUT",
        headers=cloudflare_headers(config.api_token),
        payload=payload,
    )

    if is_auth_failure(status_code, body):
        raise UpdaterError(EXIT_AUTH, "Cloudflare authentication failed")
    if status_code >= 400 or not body.get("success", False):
        summary = cloudflare_error_summary(body, "Cloudflare update failed")
        raise UpdaterError(EXIT_UPDATE, f"Cloudflare update failed: {summary}")


def parse_args(argv: Optional[list[str]]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="One-shot DDNS updater (run from cron/systemd/Kubernetes scheduler)."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Perform checks and show what would change without updating DNS records.",
    )
    parser.add_argument(
        "--service",
        help=f"DNS provider service name (default: {DEFAULT_SERVICE}).",
    )
    return parser.parse_args(argv)


def run(argv: Optional[list[str]] = None, environ: Optional[Dict[str, str]] = None) -> int:
    try:
        args = parse_args(argv)

        env = dict(os.environ if environ is None else environ)
        dotenv_path = env.get("DDNS_ENV_FILE", ".env")
        for key, value in load_dotenv(dotenv_path).items():
            env.setdefault(key, value)

        service = (args.service or env.get("DDNS_SERVICE") or DEFAULT_SERVICE).strip().lower()
        if service != "cloudflare":
            raise UpdaterError(
                EXIT_UNSUPPORTED_PROVIDER,
                f"unsupported service '{service}'; currently supported: cloudflare",
            )

        config = load_cloudflare_config(env)
        public_ip = fetch_public_ip(config.record_type)
        record = cloudflare_lookup_record(config)

        record_content = str(record.get("content", "")).strip()
        if record_content == public_ip:
            log_info(f"No change for {config.record_name} ({config.record_type})")
            return EXIT_SUCCESS

        if args.dry_run:
            log_info(
                f"Dry-run: would update {config.record_name} ({config.record_type}) "
                f"from {record_content or 'unset'} to {public_ip}"
            )
            return EXIT_SUCCESS

        cloudflare_update_record(config, record, public_ip)
        log_info(f"Updated {config.record_name} ({config.record_type}) to {public_ip}")
        return EXIT_SUCCESS
    except UpdaterError as exc:
        log_error(str(exc))
        return exc.exit_code
    except Exception:
        log_error("unexpected updater failure")
        return EXIT_UPDATE


def main(argv: Optional[list[str]] = None) -> int:
    return run(argv)


if __name__ == "__main__":
    raise SystemExit(main())
