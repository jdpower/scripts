import os
import tempfile
import unittest
from unittest import mock

import updater


class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.env = {
            "CF_API_TOKEN": "token",
            "CF_ZONE_ID": "zone-id",
            "CF_RECORD_NAME": "home.example.com",
            "CF_RECORD_TYPE": "A",
            "CF_RECORD_ID": "",
            "DDNS_ENV_FILE": "/does/not/exist",
        }

    @mock.patch("updater.fetch_public_ip")
    @mock.patch("updater.log_error")
    def test_config_validation_missing_required_value(self, log_error_mock, fetch_public_ip_mock):
        env = dict(self.env)
        env.pop("CF_API_TOKEN")
        exit_code = updater.run([], environ=env)
        self.assertEqual(exit_code, updater.EXIT_CONFIG)
        fetch_public_ip_mock.assert_not_called()
        log_error_mock.assert_called_once_with("missing required configuration: CF_API_TOKEN")

    @mock.patch("updater.fetch_public_ip")
    @mock.patch("updater.log_error")
    def test_config_validation_invalid_record_type(self, log_error_mock, fetch_public_ip_mock):
        env = dict(self.env)
        env["CF_RECORD_TYPE"] = "TXT"

        exit_code = updater.run([], environ=env)

        self.assertEqual(exit_code, updater.EXIT_CONFIG)
        fetch_public_ip_mock.assert_not_called()
        log_error_mock.assert_called_once_with(
            "CF_RECORD_TYPE must be A or AAAA"
        )

    def test_config_validation_reports_var_names(self):
        env = dict(self.env)
        env.pop("CF_API_TOKEN")
        env.pop("CF_ZONE_ID")
        with mock.patch("updater.log_error") as log_mock:
            updater.run([], environ=env)
        logged = log_mock.call_args[0][0]
        self.assertIn("CF_API_TOKEN", logged)
        self.assertIn("CF_ZONE_ID", logged)

    def test_config_validation_reports_cf_prefix_var_names(self):
        env = dict(self.env)
        env.pop("CF_API_TOKEN")
        env.pop("CF_ZONE_ID")
        with mock.patch("updater.log_error") as log_mock:
            updater.run([], environ=env)
        logged = log_mock.call_args[0][0]
        self.assertIn("CF_API_TOKEN", logged)
        self.assertIn("CF_ZONE_ID", logged)

    def test_unsupported_provider(self):
        exit_code = updater.run(["--service", "example"], environ=self.env)
        self.assertEqual(exit_code, updater.EXIT_UNSUPPORTED_PROVIDER)

    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_dry_run_does_not_update(
        self, fetch_public_ip_mock, cloudflare_lookup_record_mock, cloudflare_update_record_mock
    ):
        fetch_public_ip_mock.return_value = "203.0.113.1"
        cloudflare_lookup_record_mock.return_value = {
            "id": "record-id",
            "name": "home.example.com",
            "type": "A",
            "content": "203.0.113.2",
            "ttl": 1,
            "proxied": False,
        }

        exit_code = updater.run(["--dry-run"], environ=self.env)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        cloudflare_update_record_mock.assert_not_called()

    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_no_change_skips_update(
        self, fetch_public_ip_mock, cloudflare_lookup_record_mock, cloudflare_update_record_mock
    ):
        fetch_public_ip_mock.return_value = "203.0.113.1"
        cloudflare_lookup_record_mock.return_value = {
            "id": "record-id",
            "name": "home.example.com",
            "type": "A",
            "content": "203.0.113.1",
            "ttl": 1,
            "proxied": False,
        }

        exit_code = updater.run([], environ=self.env)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        cloudflare_update_record_mock.assert_not_called()

    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_update_needed_path(
        self, fetch_public_ip_mock, cloudflare_lookup_record_mock, cloudflare_update_record_mock
    ):
        fetch_public_ip_mock.return_value = "203.0.113.10"
        cloudflare_lookup_record_mock.return_value = {
            "id": "record-id",
            "name": "home.example.com",
            "type": "A",
            "content": "203.0.113.5",
            "ttl": 120,
            "proxied": True,
        }

        exit_code = updater.run([], environ=self.env)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        cloudflare_update_record_mock.assert_called_once()

    @mock.patch("updater.request_json")
    def test_cloudflare_lookup_auth_failure(self, request_json_mock):
        request_json_mock.return_value = (
            403,
            {
                "success": False,
                "errors": [{"code": 9109, "message": "Authentication error"}],
            },
        )

        config = updater.load_cloudflare_config(self.env)
        with self.assertRaises(updater.UpdaterError) as context:
            updater.cloudflare_lookup_record(config)

        self.assertEqual(context.exception.exit_code, updater.EXIT_AUTH)

    @mock.patch("updater.request_json")
    def test_cloudflare_lookup_not_found(self, request_json_mock):
        request_json_mock.return_value = (200, {"success": True, "result": []})

        config = updater.load_cloudflare_config(self.env)
        with self.assertRaises(updater.UpdaterError) as context:
            updater.cloudflare_lookup_record(config)

        self.assertEqual(context.exception.exit_code, updater.EXIT_LOOKUP)

    def test_loads_env_file(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            env_path = os.path.join(tmp_dir, ".env")
            with open(env_path, "w", encoding="utf-8") as dotenv:
                dotenv.write("CF_API_TOKEN=token\n")
                dotenv.write("CF_ZONE_ID=zone-id\n")
                dotenv.write("CF_RECORD_NAME=home.example.com\n")
                dotenv.write("CF_RECORD_TYPE=A\n")

            env = {"DDNS_ENV_FILE": env_path}
            with mock.patch("updater.fetch_public_ip", return_value="203.0.113.1"), mock.patch(
                "updater.cloudflare_lookup_record",
                return_value={
                    "id": "record-id",
                    "name": "home.example.com",
                    "type": "A",
                    "content": "203.0.113.1",
                },
            ), mock.patch("updater.cloudflare_update_record") as update_mock:
                exit_code = updater.run([], environ=env)

            self.assertEqual(exit_code, updater.EXIT_SUCCESS)
            update_mock.assert_not_called()


class PollingModeTests(unittest.TestCase):
    def setUp(self):
        self.env = {
            "CF_API_TOKEN": "token",
            "CF_ZONE_ID": "zone-id",
            "CF_RECORD_NAME": "home.example.com",
            "CF_RECORD_TYPE": "A",
            "CF_RECORD_ID": "",
            "DDNS_ENV_FILE": "/does/not/exist",
        }
        self._record = {
            "id": "record-id",
            "name": "home.example.com",
            "type": "A",
            "content": "203.0.113.1",
            "ttl": 1,
            "proxied": False,
        }

    @mock.patch("updater.time.sleep", side_effect=KeyboardInterrupt)
    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_polling_mode_interval_seconds_flag(
        self, fetch_ip_mock, lookup_mock, update_mock, sleep_mock
    ):
        fetch_ip_mock.return_value = "203.0.113.1"
        lookup_mock.return_value = self._record

        exit_code = updater.run(["--interval-seconds", "300"], environ=self.env)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        sleep_mock.assert_called_once_with(300)
        fetch_ip_mock.assert_called_once()

    @mock.patch("updater.time.sleep", side_effect=KeyboardInterrupt)
    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_polling_mode_ddns_interval_seconds_env_var(
        self, fetch_ip_mock, lookup_mock, update_mock, sleep_mock
    ):
        fetch_ip_mock.return_value = "203.0.113.1"
        lookup_mock.return_value = self._record

        env = dict(self.env)
        env["DDNS_INTERVAL_SECONDS"] = "300"
        exit_code = updater.run([], environ=env)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        sleep_mock.assert_called_once_with(300)

    @mock.patch("updater.time.sleep", side_effect=KeyboardInterrupt)
    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_interval_flag_overrides_env_var(
        self, fetch_ip_mock, lookup_mock, update_mock, sleep_mock
    ):
        """CLI --interval-seconds takes precedence over DDNS_INTERVAL_SECONDS."""
        fetch_ip_mock.return_value = "203.0.113.1"
        lookup_mock.return_value = self._record

        env = dict(self.env)
        env["DDNS_INTERVAL_SECONDS"] = "600"  # env var says 600
        exit_code = updater.run(["--interval-seconds", "300"], environ=env)  # CLI says 300

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        sleep_mock.assert_called_once_with(300)  # CLI value wins

    def test_polling_mode_invalid_interval_env_var(self):
        env = dict(self.env)
        env["DDNS_INTERVAL_SECONDS"] = "not-a-number"
        exit_code = updater.run([], environ=env)
        self.assertEqual(exit_code, updater.EXIT_CONFIG)

    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_one_shot_mode_no_interval(
        self, fetch_ip_mock, lookup_mock, update_mock
    ):
        """Without interval, runs once and exits (no sleep called)."""
        fetch_ip_mock.return_value = "203.0.113.1"
        lookup_mock.return_value = self._record

        with mock.patch("updater.time.sleep") as sleep_mock:
            exit_code = updater.run([], environ=self.env)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        sleep_mock.assert_not_called()

    @mock.patch("updater.time.sleep", side_effect=KeyboardInterrupt)
    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_graceful_shutdown_on_keyboard_interrupt(
        self, fetch_ip_mock, lookup_mock, update_mock, sleep_mock
    ):
        """KeyboardInterrupt (SIGINT) during polling exits with code 0."""
        fetch_ip_mock.return_value = "203.0.113.1"
        lookup_mock.return_value = self._record

        exit_code = updater.run(["--interval-seconds", "60"], environ=self.env)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)

    @mock.patch("updater.time.sleep", side_effect=KeyboardInterrupt)
    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_graceful_shutdown_on_sigterm(
        self, fetch_ip_mock, lookup_mock, update_mock, sleep_mock
    ):
        """SIGTERM during polling exits with code 0 (handler raises KeyboardInterrupt)."""
        fetch_ip_mock.return_value = "203.0.113.1"
        lookup_mock.return_value = self._record

        with mock.patch("updater.signal.signal") as signal_mock:
            exit_code = updater.run(["--interval-seconds", "60"], environ=self.env)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        # Verify SIGTERM handler was registered
        import signal as _signal
        signal_mock.assert_called_once_with(_signal.SIGTERM, updater._handle_sigterm)

    @mock.patch("updater.time.sleep", side_effect=KeyboardInterrupt)
    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_polling_dry_run_does_not_update(
        self, fetch_ip_mock, lookup_mock, update_mock, sleep_mock
    ):
        """Dry-run in polling mode never calls update."""
        fetch_ip_mock.return_value = "203.0.113.99"
        lookup_mock.return_value = dict(self._record, content="203.0.113.1")

        exit_code = updater.run(["--interval-seconds", "300", "--dry-run"], environ=self.env)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        update_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
