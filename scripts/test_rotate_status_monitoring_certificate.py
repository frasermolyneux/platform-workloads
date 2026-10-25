from datetime import datetime, timedelta, timezone
import base64
import json
import unittest
from unittest.mock import patch

import rotate_status_monitoring_certificate as rotation


class ReaderCertificateTests(unittest.TestCase):
    def test_successful_empty_cli_response_is_not_a_json_failure(self):
        with patch.object(rotation, "command", return_value=""):
            self.assertIsNone(rotation.az_json("ad", "app", "credential", "delete"))

    def setUp(self):
        self.now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        self.app = {"id": "application-object", "appId": "client-id"}
        self.key = {"keyId": "old-key", "displayName": rotation.PREFIX + "old",
                    "endDateTime": (self.now + timedelta(days=90)).isoformat()}
        self.secret = {
            "tags": {"managed-by": rotation.OWNER, "purpose": "status-monitoring-reader",
                     "application-id": "client-id", "application-object-id": "application-object",
                     "credential-key-id": "old-key"},
            "properties": {"attributes": {"enabled": True, "exp": int((self.now + timedelta(days=90)).timestamp())}}
        }

    def test_valid_certificate_is_idempotent_and_never_reads_private_key(self):
        with patch.object(rotation, "request", return_value=self.secret) as api, \
                patch.object(rotation, "credentials", return_value=[self.key]), \
                patch.object(rotation, "publish_certificate") as publish:
            rotation.rotate(self.app, "tenant", "/vault", "token", self.now)
            publish.assert_not_called()
            api.assert_called_once_with("GET",
                f"{rotation.ARM}/vault/secrets/{rotation.SECRET_NAME}?api-version=2023-07-01",
                "token", missing_ok=True)

    def test_renewal_preserves_unexpired_and_unrelated_keys_and_only_cleans_expired_managed_keys(self):
        self.secret["properties"]["attributes"]["exp"] = int((self.now + timedelta(days=20)).timestamp())
        expired = self.key | {"keyId": "expired", "endDateTime": (self.now - timedelta(days=8)).isoformat()}
        unrelated = expired | {"keyId": "unrelated", "displayName": None}
        grace = expired | {"keyId": "grace", "endDateTime": (self.now - timedelta(days=6)).isoformat()}
        calls = []
        with patch.object(rotation, "request", return_value=self.secret), \
                patch.object(rotation, "credentials", return_value=[self.key, expired, unrelated, grace]), \
                patch.object(rotation, "publish_certificate", side_effect=lambda *_: calls.append("publish")), \
                patch.object(rotation, "az_json", side_effect=lambda *_: calls.append("delete")) as cli:
            rotation.rotate(self.app, "tenant", "/vault", "token", self.now)
            self.assertEqual(calls, ["publish", "delete"])
            cli.assert_called_once_with("ad", "app", "credential", "delete", "--id", "application-object",
                                        "--key-id", "expired", "--cert")

    def test_unowned_secret_is_not_adopted_or_replaced(self):
        self.secret["tags"]["managed-by"] = "someone-else"
        with patch.object(rotation, "request", return_value=self.secret), \
                patch.object(rotation, "credentials", return_value=[self.key]), \
                patch.object(rotation, "publish_certificate") as publish:
            with self.assertRaises(rotation.RotationError):
                rotation.rotate(self.app, "tenant", "/vault", "token", self.now)
            publish.assert_not_called()

    def test_missing_public_key_renews_even_if_private_secret_metadata_is_not_expiring(self):
        with patch.object(rotation, "request", return_value=self.secret), \
                patch.object(rotation, "credentials", return_value=[]), \
                patch.object(rotation, "publish_certificate") as publish:
            rotation.rotate(self.app, "tenant", "/vault", "token", self.now)
            publish.assert_called_once()

    def test_public_registration_waits_for_directory_visibility_without_registering_again(self):
        with patch.object(rotation, "credentials", side_effect=[[], [], [self.key]]) as read, \
                patch.object(rotation.time, "sleep") as sleep:
            result = rotation.registered_certificate(self.app, self.key["displayName"],
                                                     self.now + timedelta(days=90))
            self.assertEqual(result, self.key)
            self.assertEqual(read.call_count, 3)
            self.assertEqual(sleep.call_args_list, [unittest.mock.call(5), unittest.mock.call(5)])

    def test_unverified_or_short_lived_registration_never_passes_after_bounded_retries(self):
        for registered in ([], [self.key]):
            with self.subTest(registered=registered), \
                    patch.object(rotation, "credentials", return_value=registered) as read, \
                    patch.object(rotation.time, "sleep") as sleep:
                with self.assertRaises(rotation.RotationError):
                    rotation.registered_certificate(self.app, self.key["displayName"],
                                                    self.now + timedelta(days=180))
                self.assertEqual(read.call_count, 12)
                self.assertEqual(sleep.call_count, 11)

    def test_failed_publication_does_not_delete_any_previous_credentials(self):
        with patch.object(rotation, "request", return_value=None), \
                patch.object(rotation, "credentials", return_value=[self.key]), \
                patch.object(rotation, "publish_certificate", side_effect=rotation.RotationError("failed")), \
                patch.object(rotation, "az_json") as cli:
            with self.assertRaises(rotation.RotationError):
                rotation.rotate(self.app, "tenant", "/vault", "token", self.now)
            cli.assert_not_called()

    def test_public_registration_and_authentication_precede_private_secret_publication(self):
        calls = []
        expiry = self.now + timedelta(days=180)

        def openssl(*arguments, **_kwargs):
            if arguments[1] == "req":
                from pathlib import Path
                Path(arguments[arguments.index("-keyout") + 1]).write_text("PRIVATE_FIXTURE")
                Path(arguments[arguments.index("-out") + 1]).write_text("PUBLIC_FIXTURE")
                return ""
            return "notAfter=" + expiry.strftime("%b %d %H:%M:%S %Y GMT")

        def register(*arguments):
            self.assertIn("--append", arguments)
            calls.append("register")

        registered = {"displayName": rotation.PREFIX + "fixture", "keyId": "new-key",
                      "endDateTime": expiry.isoformat()}
        for authentication_succeeds in (True, False):
            calls.clear()

            def authenticate(*_):
                if not authentication_succeeds:
                    raise rotation.RotationError("failed")
                calls.append("authenticate")

            with self.subTest(authentication_succeeds=authentication_succeeds), \
                    patch.object(rotation, "command", side_effect=openssl), \
                    patch.object(rotation.uuid, "uuid4", return_value="fixture"), \
                    patch.object(rotation, "az_json", side_effect=register), \
                    patch.object(rotation, "credentials", return_value=[registered]), \
                    patch.object(rotation, "verify_authentication", side_effect=authenticate), \
                    patch.object(rotation, "request", side_effect=lambda *_: calls.append("publish")):
                if authentication_succeeds:
                    rotation.publish_certificate(self.app, "tenant", "url", "token", self.now)
                    self.assertEqual(calls, ["register", "authenticate", "publish"])
                else:
                    with self.assertRaises(rotation.RotationError):
                        rotation.publish_certificate(self.app, "tenant", "url", "token", self.now)
                    self.assertEqual(calls, ["register"])

    def test_generated_certificate_authenticates_before_its_bundle_is_published(self):
        registered = []
        calls = []

        def register(*arguments):
            registered.append({
                "displayName": arguments[arguments.index("--display-name") + 1],
                "endDateTime": arguments[arguments.index("--end-date") + 1], "keyId": "generated-key"
            })
            calls.append("register")

        def api(method, url, token=None, document=None, **kwargs):
            if method == "POST":
                self.assertTrue(kwargs["form"])
                assertion = document["client_assertion"].split(".")
                claims = json.loads(base64.urlsafe_b64decode(assertion[1] + "=" * (-len(assertion[1]) % 4)))
                self.assertEqual(claims["aud"], url)
                self.assertEqual(claims["iss"], self.app["appId"])
                self.assertEqual(claims["sub"], self.app["appId"])
                self.assertTrue(assertion[2])
                calls.append("authenticate")
                return {"access_token": "TOKEN_FIXTURE"}
            self.assertEqual(method, "PUT")
            self.assertIn("-----BEGIN CERTIFICATE-----", document["properties"]["value"])
            self.assertIn("-----BEGIN PRIVATE KEY-----", document["properties"]["value"])
            self.assertEqual(document["tags"]["credential-key-id"], "generated-key")
            calls.append("publish")
            return {}

        with patch.object(rotation, "az_json", side_effect=register), \
                patch.object(rotation, "credentials", return_value=registered), \
                patch.object(rotation, "request", side_effect=api):
            rotation.publish_certificate(self.app, "tenant", "vault-url", "arm-token", datetime.now(timezone.utc))
        self.assertEqual(calls, ["register", "authenticate", "publish"])


if __name__ == "__main__":
    unittest.main()
