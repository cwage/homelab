"""Offline failure-path tests: no real keys, issuance, hosts or notifications."""

import contextlib
import io
import json
from pathlib import Path
import ssl
import tempfile
from typing import Any
import unittest
from unittest.mock import patch

import certificate as job


class CertificateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cfg: dict[str, Any] = {
            "state_dir": self.temp.name,
            "endpoints": [{"host": "bao.example.test", "port": 8200}],
            "propagation_seconds": 0,
            "domain": "example.test",
            "renew_days": 30,
            "compose_file": "/test/compose.yml",
            "cloudflare_token_file": "/test/cloudflare-token",
            "email": "operator@example.test",
        }
        self.now = 1000000
        self.clock = patch.object(job.time, "time", return_value=self.now)
        self.clock.start()
        self.addCleanup(self.clock.stop)
        self.stored = {
            "data": {
                "metadata": {"version": 7},
                "data": {"certificate": "stored", "extra": "preserve"},
            }
        }

    def info(self, days):
        return "fingerprint", self.now + days * 86400

    def local_files(self):
        directory = Path(self.temp.name) / "certs" / "certificates"
        directory.mkdir(parents=True)
        for suffix in ["crt", "key", "issuer.crt"]:
            (directory / f"_.example.test.{suffix}").write_text("fixture-placeholder")
        return directory

    def test_no_issuance_when_stored_certificate_is_healthy(self):
        with (
            patch.object(job, "bao_request", return_value=self.stored),
            patch.object(job, "certificate_info", return_value=self.info(60)),
            patch.object(job, "run") as run,
            patch.object(job, "verify_propagation") as verify,
        ):
            job.renew(self.cfg)
        run.assert_not_called()
        verify.assert_called_once_with(self.cfg, "fingerprint")

    def test_initial_issuance_only_when_due(self):
        with (
            patch.object(job, "bao_request", return_value=self.stored),
            patch.object(job, "certificate_info", return_value=self.info(29)),
            patch.object(job, "run") as run,
            patch.object(job, "publish", return_value="new") as publish,
            patch.object(job, "verify_propagation") as verify,
        ):
            job.renew(self.cfg)
        self.assertEqual(run.call_args.args[0][-1], "run")
        self.assertIn(
            "CF_DNS_API_TOKEN_FILE=/run/secrets/cloudflare-token", run.call_args.args[0]
        )
        publish.assert_called_once()
        verify.assert_called_once_with(self.cfg, "new")

    def test_existing_state_renews_instead_of_registering_again(self):
        self.local_files()
        with (
            patch.object(job, "bao_request", return_value=self.stored),
            patch.object(job, "certificate_info", return_value=self.info(29)),
            patch.object(job, "run") as run,
            patch.object(job, "publish", return_value="new"),
            patch.object(job, "verify_propagation"),
        ):
            job.renew(self.cfg)
        self.assertEqual(
            run.call_args.args[0][-3:], ["renew", "--days=30", "--no-random-sleep"]
        )

    def test_retry_failed_publication_without_new_issuance(self):
        self.local_files()
        with (
            patch.object(job, "bao_request", return_value=self.stored),
            patch.object(
                job, "certificate_info", side_effect=[self.info(29), self.info(90)]
            ),
            patch.object(job, "run") as run,
            patch.object(job, "publish", return_value="pending") as publish,
            patch.object(job, "verify_propagation") as verify,
        ):
            job.renew(self.cfg)
        run.assert_not_called()
        publish.assert_called_once()
        verify.assert_called_once_with(self.cfg, "pending")

    def test_issuance_failure_never_publishes(self):
        with (
            patch.object(job, "bao_request", return_value=self.stored),
            patch.object(job, "certificate_info", return_value=self.info(29)),
            patch.object(job, "run", side_effect=job.JobError("issuance failed")),
            patch.object(job, "publish") as publish,
        ):
            with self.assertRaises(job.JobError):
                job.renew(self.cfg)
        publish.assert_not_called()

    def test_publish_uses_cas_and_preserves_other_fields(self):
        directory = self.local_files()
        with (
            patch.object(
                job, "certificate_info", side_effect=[self.info(90), self.info(29)]
            ),
            patch.object(job.ssl, "create_default_context"),
            patch.object(job, "run"),
            patch.object(job, "bao_request") as request,
        ):
            job.publish(self.cfg, self.stored, directory)
        payload = request.call_args.args[1]
        self.assertEqual(payload["options"], {"cas": 7})
        self.assertEqual(payload["data"]["extra"], "preserve")

    def test_reject_untrusted_certificate_before_publication(self):
        directory = self.local_files()
        with (
            patch.object(
                job, "certificate_info", side_effect=[self.info(90), self.info(29)]
            ),
            patch.object(job.ssl, "create_default_context"),
            patch.object(job, "run", side_effect=job.JobError("validation failed")),
            patch.object(job, "bao_request") as request,
        ):
            with self.assertRaises(job.JobError):
                job.publish(self.cfg, self.stored, directory)
        request.assert_not_called()

    def test_reject_certificate_that_does_not_extend_validity(self):
        directory = self.local_files()
        with (
            patch.object(
                job, "certificate_info", side_effect=[self.info(40), self.info(60)]
            ),
            patch.object(job, "bao_request") as request,
        ):
            with self.assertRaises(job.JobError):
                job.publish(self.cfg, self.stored, directory)
        request.assert_not_called()

    def test_stale_or_unreachable_listener_fails_propagation(self):
        for result in [self.info(29), OSError("connection failed")]:
            with (
                self.subTest(result=result),
                patch.object(job, "probe", side_effect=[result]),
            ):
                with self.assertRaisesRegex(job.JobError, "propagation failed"):
                    job.verify_propagation(self.cfg, "new-fingerprint")

    def test_monitor_deduplicates_escalates_and_clears_on_recovery(self):
        with patch.object(job, "probe") as probe, patch.object(job, "notify") as notify:
            for days in [20, 19, 6, 5, 1, 1, 90, 20]:
                probe.return_value = self.info(days)
                job.monitor(self.cfg)
        self.assertEqual(
            [call.args[3] for call in notify.call_args_list],
            ["default", "high", "urgent", "default"],
        )

    def test_monitor_retries_failed_notification(self):
        with (
            patch.object(job, "probe", return_value=self.info(6)),
            patch.object(
                job, "notify", side_effect=[OSError("offline"), None]
            ) as notify,
        ):
            with self.assertRaises(job.JobError):
                job.monitor(self.cfg)
            job.monitor(self.cfg)
        self.assertEqual(notify.call_count, 2)

    def test_monitor_handles_tls_failure_and_still_checks_other_endpoint(self):
        self.cfg["endpoints"].append({"host": "traefik.example.test", "port": 443})
        with (
            patch.object(
                job, "probe", side_effect=[ssl.SSLError("expired"), self.info(6)]
            ),
            patch.object(job, "notify") as notify,
        ):
            job.monitor(self.cfg)
        self.assertEqual(notify.call_count, 2)
        self.assertEqual(notify.call_args_list[0].args[3], "urgent")

    def test_arbitrary_exception_content_is_not_logged(self):
        config_file = Path(self.temp.name) / "config.json"
        config_file.write_text(json.dumps(self.cfg))
        output = io.StringIO()
        with (
            patch.object(
                job.sys, "argv", ["certificate.py", "renew", str(config_file)]
            ),
            patch.object(
                job, "renew", side_effect=RuntimeError("sensitive-response-placeholder")
            ),
            contextlib.redirect_stderr(output),
        ):
            self.assertEqual(job.main(), 1)
        self.assertNotIn("sensitive-response-placeholder", output.getvalue())

    def test_probe_uses_hostname_verification_and_sni(self):
        with (
            patch.object(job.ssl, "create_default_context") as create,
            patch.object(job.socket, "create_connection"),
        ):
            connection = (
                create.return_value.wrap_socket.return_value.__enter__.return_value
            )
            connection.getpeercert.side_effect = [
                b"public-der-fixture",
                {"notAfter": "Oct 26 12:00:00 2026 GMT"},
            ]
            job.probe(self.cfg["endpoints"][0])
            self.assertEqual(
                create.return_value.wrap_socket.call_args.kwargs["server_hostname"],
                "bao.example.test",
            )


if __name__ == "__main__":
    unittest.main()
