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
            "invalid configuration: CF_RECORD_TYPE must be A or AAAA"
        )

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

    @mock.patch("updater.install_signal_handlers")
    @mock.patch("updater.cloudflare_update_record")
    @mock.patch("updater.cloudflare_lookup_record")
    @mock.patch("updater.fetch_public_ip")
    def test_interval_mode_runs_cycle_then_stops_cleanly(
        self,
        fetch_public_ip_mock,
        cloudflare_lookup_record_mock,
        cloudflare_update_record_mock,
        install_signal_handlers_mock,
    ):
        class FakeStopEvent:
            def __init__(self):
                self.wait_calls = []

            def is_set(self):
                return False

            def set(self):
                return None

            def wait(self, seconds):
                self.wait_calls.append(seconds)
                return True

        stop_event = FakeStopEvent()
        fetch_public_ip_mock.return_value = "203.0.113.1"
        cloudflare_lookup_record_mock.return_value = {
            "id": "record-id",
            "name": "home.example.com",
            "type": "A",
            "content": "203.0.113.1",
        }

        with mock.patch("updater.log_info") as log_info_mock:
            exit_code = updater.run(["--interval", "300"], environ=self.env, stop_event=stop_event)

        self.assertEqual(exit_code, updater.EXIT_SUCCESS)
        install_signal_handlers_mock.assert_called_once_with(stop_event)
        cloudflare_update_record_mock.assert_not_called()
        self.assertEqual(stop_event.wait_calls, [300])
        self.assertTrue(
            any("Polling stopped; exiting cleanly." in call.args[0] for call in log_info_mock.call_args_list)
        )

    def test_install_signal_handlers_sets_stop_event(self):
        registered_handlers = {}

        def capture_handler(signal_value, handler):
            registered_handlers[signal_value] = handler

        stop_event = mock.Mock()
        stop_event.is_set.return_value = False

        with mock.patch("updater.signal.signal", side_effect=capture_handler), mock.patch(
            "updater.log_info"
        ) as log_info_mock:
            updater.install_signal_handlers(stop_event)
            handler = registered_handlers[updater.signal.SIGTERM]
            handler(updater.signal.SIGTERM, None)

        stop_event.set.assert_called_once_with()
        log_info_mock.assert_called_with("Received SIGTERM; shutting down cleanly.")


if __name__ == "__main__":
    unittest.main()
