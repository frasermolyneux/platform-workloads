import copy
import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlparse
from urllib.request import urlopen

import bootstrap_github_app as bootstrap


class GitHubAppBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.app = {
            "display_name": "Status fixture", "description": "Approved incidents", "owner": "fixture",
            "owner_type": "User", "homepage_url": "https://status.example.com", "environment": "prd",
            "repositories": ["status-pages"], "repository_permissions": {"issues": "write"},
            "key_vault_secret_name": "github-incidents-private-key", "registration": None
        }
        self.identity = {"id": 42, "slug": "status-fixture", "pem": "PRIVATE_KEY_FIXTURE"}
        self.installation = {"id": 100, "account": {"login": "fixture"},
                             "repository_selection": "selected", "permissions": {"issues": "write", "metadata": "read"}}

    def test_manifest_uses_reviewed_permissions_and_no_events_or_oauth(self):
        value = bootstrap.manifest(self.app, "http://127.0.0.1:1234/callback")
        self.assertEqual(value["default_permissions"], {"issues": "write"})
        self.assertFalse(value["public"])
        self.assertFalse(value["hook_attributes"]["active"])
        self.assertEqual(value["default_events"], [])
        self.assertNotIn("request_oauth_on_install", value)

    def test_callback_rejects_wrong_state_duplicate_parameters_and_wrong_routes(self):
        self.assertEqual(bootstrap.callback_code("/callback?state=approved&code=abc123", "approved"), "abc123")
        for path in ("/callback?state=other&code=abc123", "/callback?state=approved",
                     "/callback?state=approved&code=a&code=b", "/callback?state=approved&state=other&code=a",
                     "/other?state=approved&code=a", "/callback?state=approved&code=../unsafe"):
            with self.subTest(path=path):
                self.assertIsNone(bootstrap.callback_code(path, "approved"))

    def test_browser_registration_serves_manifest_and_exchanges_only_a_valid_callback(self):
        failures = []
        threads = []

        def open_browser(link):
            def browse():
                try:
                    with urlopen(link, timeout=5) as page:
                        document = page.read().decode()
                    self.assertIn("issues", document)
                    self.assertIn("write", document)
                    self.assertIn('method="post"', document)
                    origin = urlparse(link)
                    state = parse_qs(origin.query)["state"][0]
                    with urlopen(f"http://{origin.netloc}/callback?state={state}&code=approval-code", timeout=5) as callback:
                        self.assertEqual(callback.status, 200)
                except Exception as error:
                    failures.append(error)
            thread = threading.Thread(target=browse)
            thread.start()
            threads.append(thread)
        with patch.object(bootstrap.webbrowser, "open", side_effect=open_browser), \
             patch.object(bootstrap, "request_json", return_value=self.identity) as api, \
             patch("sys.stdout", new_callable=io.StringIO):
            self.assertEqual(bootstrap.create_app(self.app, timeout=10), self.identity)
            for thread in threads:
                thread.join(timeout=5)
            self.assertEqual(failures, [])
            api.assert_called_once_with("POST", f"{bootstrap.API}/app-manifests/approval-code/conversions")

    def test_verification_rejects_broader_installations_without_minting_a_token(self):
        for changed in ({"repository_selection": "all"}, {"permissions": {"issues": "write", "contents": "write"}},
                        {"suspended_at": "2026-01-01"}, {"account": {"login": "another-owner"}}):
            with self.subTest(changed=changed), patch.object(bootstrap, "request_json") as api:
                with self.assertRaises(bootstrap.BootstrapError):
                    bootstrap.verify_installation(self.identity, self.app, self.installation | changed)
                api.assert_not_called()

    def test_repository_scope_is_verified_and_temporary_token_revoked_on_success_or_failure(self):
        for repositories, count, valid in ((["fixture/status-pages"], 1, True),
                                           (["fixture/status-pages", "fixture/another"], 2, False),
                                           (["fixture/status-pages"], 101, False)):
            with self.subTest(repositories=repositories, count=count), patch.object(bootstrap, "app_jwt", return_value="jwt"):
                response = {"total_count": count, "repositories": [{"full_name": name} for name in repositories]}
                with patch.object(bootstrap, "request_json", side_effect=[{"token": "temporary"}, response, None]) as api:
                    if valid:
                        bootstrap.verify_installation(self.identity, self.app, self.installation)
                    else:
                        with self.assertRaises(bootstrap.BootstrapError):
                            bootstrap.verify_installation(self.identity, self.app, self.installation)
                    self.assertEqual(api.call_args.args, ("DELETE", f"{bootstrap.API}/installation/token"))
                    self.assertEqual(api.call_args.kwargs["token"], "temporary")

    def test_existing_unknown_key_is_not_adopted_or_overwritten(self):
        with patch.object(bootstrap, "az_json", return_value=[{"name": self.app["key_vault_secret_name"].upper()}]), \
             patch.object(bootstrap, "vault_request", return_value={"value": "unowned", "attributes": {"enabled": True}}):
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.read_existing("vault", self.app, "workload", "status-incidents", "token")

    def test_resume_reuses_vault_key_without_creating_or_writing_another_key(self):
        with patch.object(bootstrap, "bootstrap_lock"), \
             patch.object(bootstrap, "load_app", return_value=(Path("catalog"), {}, self.app)), \
             patch.object(bootstrap, "discover_vault", return_value="vault"), \
             patch.object(bootstrap, "az_json", return_value={"accessToken": "azure-token"}), \
             patch.object(bootstrap, "read_existing", return_value=self.identity), \
             patch.object(bootstrap, "validate_identity"), \
             patch.object(bootstrap, "wait_installation", return_value=100), \
             patch.object(bootstrap, "save_registration") as save, \
             patch.object(bootstrap, "create_app") as create, \
             patch.object(bootstrap, "vault_request") as vault, patch("sys.stdout", new_callable=io.StringIO) as output:
            bootstrap.bootstrap("workload", "status-incidents", browser=False)
            create.assert_not_called()
            vault.assert_not_called()
            self.assertEqual(save.call_args.args[-1], 100)
            self.assertNotIn("PRIVATE_KEY_FIXTURE", output.getvalue())

    def test_registration_refreshes_vault_credentials_after_browser_approval(self):
        with patch.object(bootstrap, "bootstrap_lock"), \
             patch.object(bootstrap, "load_app", return_value=(Path("catalog"), {}, self.app)), \
             patch.object(bootstrap, "discover_vault", return_value="vault"), \
             patch.object(bootstrap, "az_json", side_effect=[{"accessToken": "old"}, {"accessToken": "fresh"}]), \
             patch.object(bootstrap, "read_existing", return_value=None) as existing, \
             patch.object(bootstrap, "create_app", return_value=self.identity), \
             patch.object(bootstrap, "validate_identity"), \
             patch.object(bootstrap, "wait_installation", return_value=100), \
             patch.object(bootstrap, "save_registration"), \
             patch.object(bootstrap, "vault_request") as vault, patch("sys.stdout", new_callable=io.StringIO):
            bootstrap.bootstrap("workload", "status-incidents", browser=False)
            self.assertEqual(existing.call_args.args[-1], "fresh")
            self.assertEqual(vault.call_args.args[3], "fresh")

    def test_shared_lease_blocks_other_bootstraps_and_is_released_after_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backend = root / "terraform" / "backends"
            backend.mkdir(parents=True)
            (backend / "prd.backend.hcl").write_text(
                'storage_account_name = "fixtureaccount"\ncontainer_name = "tfstate"\n', encoding="utf-8")
            held = False
            released = 0

            def storage(*arguments):
                nonlocal held, released
                self.assertIn("login", arguments)
                if arguments[:3] == ("storage", "blob", "exists"):
                    return {"exists": True}
                action = arguments[3]
                if action == "acquire":
                    if held:
                        raise bootstrap.BootstrapError("Another bootstrap holds the lock.")
                    held = True
                    return "fixture-lease"
                self.assertTrue(held)
                self.assertEqual(arguments[-1], "fixture-lease")
                if action == "release":
                    held = False
                    released += 1

            with patch.object(bootstrap, "ROOT", root), patch.object(bootstrap, "az_json", side_effect=storage), \
                 patch.object(bootstrap, "load_app") as load:
                with self.assertRaisesRegex(bootstrap.BootstrapError, "fixture failure"):
                    with bootstrap.bootstrap_lock() as verify:
                        verify()
                        with self.assertRaisesRegex(bootstrap.BootstrapError, "Another bootstrap"):
                            bootstrap.bootstrap("another-workload", "another-app", browser=False)
                        load.assert_not_called()
                        self.assertTrue(held)
                        raise bootstrap.BootstrapError("fixture failure")
                self.assertFalse(held)
                self.assertEqual(released, 1)

    def test_registration_preserves_unrelated_concurrent_edits_and_does_not_write_the_key(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "workload.json"
            catalog = {"github": {"runtime_apps": {"status-incidents": self.app}}, "description": "original"}
            current = copy.deepcopy(catalog)
            current["description"] = "changed during approval"
            path.write_text(json.dumps(current), encoding="utf-8")
            bootstrap.save_registration(path, catalog, "status-incidents", self.identity, 100)
            stored = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(stored["description"], "changed during approval")
            self.assertEqual(stored["github"]["runtime_apps"]["status-incidents"]["registration"]["installation_id"], "100")
            self.assertNotIn("PRIVATE", path.read_text(encoding="utf-8"))
            current["github"]["runtime_apps"]["status-incidents"]["repositories"] = ["changed"]
            path.write_text(json.dumps(current), encoding="utf-8")
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.save_registration(path, catalog, "status-incidents", self.identity, 100)

    def test_http_failures_do_not_include_callback_codes_or_response_bodies(self):
        url = "https://api.github.com/app-manifests/PRIVATE_CODE/conversions"
        error = HTTPError(url, 422, "PRIVATE_BODY", {}, io.BytesIO(b"PRIVATE_BODY"))
        with patch.object(bootstrap, "build_opener") as opener:
            opener.return_value.open.side_effect = error
            with self.assertRaises(bootstrap.BootstrapError) as result:
                bootstrap.request_json("POST", url)
            self.assertNotIn("PRIVATE", str(result.exception))

    def test_soft_deleted_key_blocks_registration_instead_of_losing_the_new_key(self):
        with patch.object(bootstrap, "az_json", side_effect=[[], [{"name": self.app["key_vault_secret_name"].upper()}]]), \
             patch.object(bootstrap, "vault_request") as vault:
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.read_existing("vault", self.app, "workload", "status-incidents", "token")
            vault.assert_not_called()

    def test_app_jwt_is_signed_with_the_app_key_and_short_lived_without_embedded_key_material(self):
        import base64
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding, rsa
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                serialization.NoEncryption()).decode()
        with patch.object(bootstrap.time, "time", return_value=10000):
            jwt = bootstrap.app_jwt(self.identity | {"pem": pem})
        header, body, signature = jwt.split(".")
        payload = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
        self.assertEqual(payload, {"iat": 9940, "exp": 10540, "iss": "42"})
        key.public_key().verify(base64.urlsafe_b64decode(signature + "=" * (-len(signature) % 4)),
                                f"{header}.{body}".encode(), padding.PKCS1v15(), hashes.SHA256())

    def test_declaration_rejects_secret_path_and_unbounded_repository_selection(self):
        for changed in ({"key_vault_secret_name": "../secret"}, {"repositories": []},
                        {"repositories": ["status-pages", "status-pages"]},
                        {"repositories": ["status-pages", "Status-Pages"]},
                        {"homepage_url": "https://user:password@example.com"},
                        {"owner": "owner/unsafe"}, {"repository_permissions": {"issues": "admin"}}):
            with self.subTest(changed=changed):
                with self.assertRaises(bootstrap.BootstrapError):
                    bootstrap.validate_app(self.app | changed)

    def test_exact_repository_selection_can_span_multiple_pages_and_always_revokes_its_token(self):
        app = self.app | {"repositories": [f"repo-{index}" for index in range(101)]}
        names = [{"full_name": f"fixture/{name}"} for name in app["repositories"]]
        for last in (names[100:], [{"full_name": "fixture/unapproved"}]):
            with self.subTest(last=last), patch.object(bootstrap, "app_jwt", return_value="jwt"), \
                 patch.object(bootstrap, "request_json", side_effect=[
                     {"token": "temporary"}, {"total_count": 101, "repositories": names[:100]},
                     {"total_count": 101, "repositories": last}, None]) as api:
                if last == names[100:]:
                    bootstrap.verify_installation(self.identity, app, self.installation)
                else:
                    with self.assertRaises(bootstrap.BootstrapError):
                        bootstrap.verify_installation(self.identity, app, self.installation)
                self.assertEqual(api.call_args_list[2].args[1], f"{bootstrap.API}/installation/repositories?per_page=100&page=2")
                self.assertEqual(api.call_args.args, ("DELETE", f"{bootstrap.API}/installation/token"))


if __name__ == "__main__":
    unittest.main()
